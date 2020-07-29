require "../framework"

class RelationshipsController
  include Balloon::Controller
  extend Balloon::Util

  skip_auth ["/actors/:username/outbox"], GET
  skip_auth ["/actors/:username/inbox"], POST, GET
  skip_auth ["/actors/:username/following"], GET
  skip_auth ["/actors/:username/followers"], GET

  post "/actors/:username/outbox" do |env|
    unless (account = get_account(env))
      not_found
    end
    unless env.current_account? == account
      forbidden
    end

    activity = env.params.body

    case activity["type"]?
    when "Follow"
      unless (iri = activity["object"]?) && (object = ActivityPub::Actor.find?(iri))
        bad_request
      end
      activity = ActivityPub::Activity::Follow.new(
        iri: "#{Balloon.host}/activities/#{id}",
        actor: account.actor,
        object: object,
        to: [object.iri]
      )
    else
      bad_request
    end

    unless activity.valid_for_send?
      bad_request
    end

    if object.local
      Relationship::Content::Inbox.new(
        owner: object,
        activity: activity
      ).save
    else
      response = HTTP::Client.post(
        (inbox = object.inbox.not_nil!),
        Balloon::Signature.sign(account.actor, inbox),
        activity.to_json_ld
      )
    end

    Relationship::Social::Follow.new(
      actor: account.actor,
      object: object
    ).save

    Relationship::Content::Outbox.new(
      owner: account.actor,
      activity: activity
    ).save

    env.redirect back_path
  end

  post "/actors/:username/inbox" do |env|
    unless (account = get_account(env))
      not_found
    end
    unless (body = env.request.body)
      bad_request
    end

    activity = ActivityPub::Activity.from_json_ld(body)

    if activity.id
      ok
    end

    if env.request.headers["Signature"]?
      # never use the embedded actor's credentials for verification! go to the source
      if (actor_iri = activity.actor_iri)
        if (actor = ActivityPub::Actor.find?(actor_iri)) && actor.pem_public_key
          unless Balloon::Signature.verify?(actor, "#{host}#{env.request.path}", env.request.headers)
            bad_request
          end
          activity.save
        else
          open(actor_iri) do |response|
            if (actor = ActivityPub::Actor.from_json_ld?(response.body, include_key: true)) && actor.pem_public_key
              unless Balloon::Signature.verify?(actor, "#{host}#{env.request.path}", env.request.headers)
                bad_request
              end
              actor.save
              activity.save
            end
          end
        end
      end
    else
      open(activity.iri) do |response|
        activity = ActivityPub::Activity.from_json_ld(response.body)
        activity.save
      end
    end

    unless activity.id
      bad_request
    end

    case activity
    when ActivityPub::Activity::Create
      unless (object = activity.object?)
        unless (object_iri = activity.object_iri)
          bad_request
        end
        open(object_iri) do |response|
          object = ActivityPub::Object.from_json_ld(response.body)
          activity.object = object
        end
      end
      Relationship::Content::Inbox.new(
        owner: account.actor,
        activity: activity
      ).save
    when ActivityPub::Activity::Accept
      unless activity.object?.try(&.local)
        bad_request
      end
      unless (follow = Relationship::Social::Follow.find?(from_iri: account.actor.iri, to_iri: activity.actor.iri))
        bad_request
      end
      follow.assign(confirmed: true).save
    when ActivityPub::Activity::Reject
      unless activity.object?.try(&.local)
        bad_request
      end
      unless (follow = Relationship::Social::Follow.find?(from_iri: account.actor.iri, to_iri: activity.actor.iri))
        bad_request
      end
      follow.assign(confirmed: false).save
    else
      bad_request
    end

    ok
  end

  get "/actors/:username/outbox" do |env|
    unless (account = get_account(env))
      not_found
    end
    activities = account.actor.in_outbox(*pagination_params(env), public: env.current_account? != account)

    if accepts?("text/html")
      env.response.content_type = "text/html"
      render "src/views/relationships/outbox.html.ecr", "src/views/layouts/default.html.ecr"
    else
      env.response.content_type = "application/json"
      render "src/views/relationships/outbox.json.ecr"
    end
  end

  get "/actors/:username/inbox" do |env|
    unless (account = get_account(env))
      not_found
    end
    activities = account.actor.in_inbox(*pagination_params(env), public: env.current_account? != account)

    if accepts?("text/html")
      env.response.content_type = "text/html"
      render "src/views/relationships/inbox.html.ecr", "src/views/layouts/default.html.ecr"
    else
      env.response.content_type = "application/json"
      render "src/views/relationships/inbox.json.ecr"
    end
  end

  get "/actors/:username/:relationship" do |env|
    unless (account = get_account(env))
      not_found
    end
    actor = account.actor
    unless (related = all_related(env, actor, public: env.current_account? != account))
      bad_request
    end

    if accepts?("text/html")
      env.response.content_type = "text/html"
      render "src/views/relationships/index.html.ecr", "src/views/layouts/default.html.ecr"
    else
      env.response.content_type = "application/json"
      render "src/views/relationships/index.json.ecr"
    end
  end

  post "/actors/:username/:relationship" do |env|
    unless (account = get_account(env))
      not_found
    end
    unless env.current_account? == account
      forbidden
    end
    actor = account.actor
    unless (other = find_other(env))
      bad_request
    end
    unless (relationship = make_relationship(env, actor, other))
      bad_request
    end
    unless relationship.valid?
      bad_request
    end

    relationship.save

    env.redirect actor_relationships_path(actor)
  end

  delete "/actors/:username/:relationship/:id" do |env|
    unless (account = get_account(env))
      not_found
    end
    unless env.current_account? == account
      forbidden
    end
    actor = account.actor
    unless (relationship = find_relationship(env))
      bad_request
    end
    unless actor.iri.in?({relationship.from_iri, relationship.to_iri})
      forbidden
    end

    relationship.destroy

    env.redirect actor_relationships_path(actor)
  end

  private def self.pagination_params(env)
    {
      env.params.query["page"]?.try(&.to_u16) || 0_u16,
      env.params.query["size"]?.try(&.to_u16) || 10_u16
    }
  end

  private def self.get_account(env)
    Account.find?(username: env.params.url["username"]?)
  end

  private def self.all_related(env, actor, public = true)
    case env.params.url["relationship"]?
    when "following"
      actor.all_following(*pagination_params(env), public: public)
    when "followers"
      actor.all_followers(*pagination_params(env), public: public)
    else
    end
  end

  private def self.make_relationship(env, actor, other)
    case env.params.url["relationship"]?
    when "following"
      actor.follow(other, confirmed: true, visible: true)
    when "followers"
      other.follow(actor, confirmed: true, visible: true)
    else
    end
  end

  private def self.find_relationship(env)
    case env.params.url["relationship"]?
    when "following"
      Relationship::Social::Follow.find?(env.params.url["id"].to_i)
    when "followers"
      Relationship::Social::Follow.find?(env.params.url["id"].to_i)
    else
    end
  end

  private def self.find_other(env)
    (iri = env.params.body["iri"]? || env.params.json["iri"]?) &&
      (other = ActivityPub::Actor.find?(iri.to_s))
    other
  end
end
