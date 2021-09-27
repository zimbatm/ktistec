require "kemal"
require "kilt/slang"

require "./ext/context"
require "../views/view_helper"

class HTTP::Server::Context
  def accepts?(*mime_types)
    @accepts ||=
      if self.request.headers["Accept"]?
        self.request.headers["Accept"].split(",").map(&.split(";").first.strip)
      elsif self.request.headers["Content-Type"]?
        [self.request.headers["Content-Type"].split(";").first.strip]
      else
        [] of String
      end
    if accepts = @accepts
      if (mime_type = mime_types.find(&.in?(accepts)))
        self.response.content_type = mime_type
      end
    end
  end

  def xhr?
    @request.headers["X-Requested-With"]? == "XMLHttpRequest"
  end

  def created(url, status_code = nil, *, body = nil)
    @response.headers.add("Location", url)
    @response.status_code = status_code.nil? ? (accepts?("text/html") && !xhr?) ? 302 : 201 : status_code
    @response.print(body) if body
  end
end

module Ktistec
  module Controller
    macro included
      # generally, controllers are going to want to use
      # view helpers in their actions.
      include Ktistec::ViewHelper
    end

    macro host
      Ktistec.host
    end

    macro home_path
      "/"
    end

    macro search_path
      "/search"
    end

    macro sessions_path
      "/sessions"
    end

    macro settings_path
      "/settings"
    end

    macro metrics_path
      "/metrics"
    end

    macro back_path
      env.request.headers.fetch("Referer", "/")
    end

    macro remote_activity_path(activity = nil)
      "/remote/activities/#{{{activity}}.try(&.id) || env.params.url["id"]}"
    end

    macro activity_path(activity = nil)
      "/activities/#{{{activity}}.try(&.uid) || env.params.url["id"]}"
    end

    macro objects_path
      "/objects"
    end

    macro remote_object_path(object = nil)
      "/remote/objects/#{{{object}}.try(&.id) || env.params.url["id"]}"
    end

    macro edit_object_path(object = nil)
      "/objects/#{{{object}}.try(&.uid) || env.params.url["id"]}/edit"
    end

    macro object_path(object = nil)
      "/objects/#{{{object}}.try(&.uid) || env.params.url["id"]}"
    end

    macro remote_actor_path(actor = nil)
      "/remote/actors/#{{{actor}}.try(&.id) || env.params.url["id"]}"
    end

    macro actor_path(actor = nil)
      "/actors/#{{{actor}}.try(&.uid) || env.params.url["username"]}"
    end

    macro actor_relationships_path(actor = nil, relationship = nil)
      "#{actor_path({{actor}})}/#{{{relationship}} || env.params.url["relationship"]}"
    end

    macro actor_remote_follow_path(actor = nil)
      "#{actor_path({{actor}})}/remote-follow"
    end

    macro outbox_path(actor = nil)
      "#{actor_path({{actor}})}/outbox"
    end

    macro inbox_path(actor = nil)
      "#{actor_path({{actor}})}/inbox"
    end

    macro anchor(object)
      "object-#{{{object}}.id}"
    end

    macro thread_path(object)
      "/objects/#{{{object}}.uid}/thread#object-#{{{object}}.id}"
    end

    macro remote_thread_path(object)
      "/remote/objects/#{{{object}}.id}/thread#object-#{{{object}}.id}"
    end

    macro reply_path(object)
      "/remote/objects/#{{{object}}.id}/reply"
    end

    macro approve_path(object)
      "/remote/objects/#{{{object}}.id}/approve"
    end

    macro unapprove_path(object)
      "/remote/objects/#{{{object}}.id}/unapprove"
    end

    macro accepts?(*mime_type)
      env.accepts?({{*mime_type}})
    end

    macro xhr?
      env.xhr?
    end

    # Redirect and end processing.
    #
    macro redirect(url, status_code = 302, body = nil)
      env.response.headers.add("Location", {{url}})
      env.response.status_code = {{status_code}}
      {% if body %}
        env.response.print({{body}})
      {% end %}
      env.response.close
      next
    end

    # Define a simple response helper.
    #
    macro def_response_helper(name, message, code)
      macro {{name.id}}(message = nil, code = nil, basedir = "src/views")
        \{% if message.is_a?(StringLiteral) && message.includes?('/') %}
          if accepts?("application/activity+json", "application/json")
            \{% if read_file?("#{basedir.id}/#{message.id}.json.ecr") %}
              halt env, status_code: \{{code}} || {{code}}, response: render \{{"#{basedir.id}/#{message.id}.json.ecr"}}
            \{% end %}
          end
          if accepts?("text/html")
            \{% if read_file?("#{basedir.id}/#{message.id}.html.ecr") %}
              halt env, status_code: \{{code}} || {{code}}, response: render \{{"#{basedir.id}/#{message.id}.html.ecr"}}, "src/views/layouts/default.html.ecr"
            \{% elsif read_file?("#{basedir.id}/#{message.id}.html.slang") %}
              halt env, status_code: \{{code}} || {{code}}, response: render \{{"#{basedir.id}/#{message.id}.html.slang"}}, "src/views/layouts/default.html.ecr"
            \{% end %}
          end
          if accepts?("text/plain")
            \{% if read_file?("#{basedir.id}/#{message.id}.text.ecr") %}
              halt env, status_code: \{{code}} || {{code}}, response: render \{{"#{basedir.id}/#{message.id}.text.ecr"}}
            \{% end %}
          end
          \{% if read_file?("#{basedir.id}/#{message.id}.json.ecr") %}
            halt env, status_code: \{{code}} || {{code}}, response: render \{{"#{basedir.id}/#{message.id}.json.ecr"}}
          \{% elsif read_file?("#{basedir.id}/#{message.id}.html.ecr") %}
              halt env, status_code: \{{code}} || {{code}}, response: render \{{"#{basedir.id}/#{message.id}.html.ecr"}}, "src/views/layouts/default.html.ecr"
          \{% elsif read_file?("#{basedir.id}/#{message.id}.html.slang") %}
              halt env, status_code: \{{code}} || {{code}}, response: render \{{"#{basedir.id}/#{message.id}.html.slang"}}, "src/views/layouts/default.html.ecr"
          \{% end %}
        \{% else %}
          if accepts?("application/activity+json", "application/json")
            halt env, status_code: \{{code}} || {{code}}, response: ({msg: (\{{message}} || {{message}}).downcase}.to_json)
          end
          if accepts?("text/html")
            _message = \{{message}} || {{message}}
            halt env, status_code: \{{code}} || {{code}}, response: render "src/views/pages/generic.html.ecr", "src/views/layouts/default.html.ecr"
          end
          if accepts?("text/plain")
            halt env, status_code: \{{code}} || {{code}}, response: (\{{message}} || {{message}}).downcase
          end
          halt env, status_code: \{{code}} || {{code}}, response: ({msg: (\{{message}} || {{message}}).downcase}.to_json)
        \{% end %}
      end
    end

    def_response_helper(ok, "OK", 200)
    def_response_helper(created, "Created", 201)
    def_response_helper(bad_request, "Bad Request", 400)
    def_response_helper(forbidden, "Forbidden", 403)
    def_response_helper(not_found, "Not Found", 404)
    def_response_helper(conflict, "Conflict", 409)
    def_response_helper(unprocessable_entity, "Unprocessable Entity", 422)
    def_response_helper(server_error, "Server Error", 500)

    # Don't authenticate specified handlers.
    #
    #     skip_auth ["/foo", "/bar"], GET, POST
    #
    macro skip_auth(paths, method = GET, *methods)
      class ::Ktistec::Auth < ::Kemal::Handler
        {% for method in (methods << method) %}
          exclude {{paths}}, {{method.stringify}}
        {% end %}
      end
    end

    # Sanitizes HTML.
    #
    # For use in views:
    #     <%= s string %>
    #
    macro s(str)
      Ktistec::Util.sanitize({{str}})
    end

    # Pluralizes the noun.
    #
    # For use in views:
    #     <%= pluralize(1, "fox") %>
    #
    macro pluralize(count, noun)
      case {{count}}
      when 0
        {{noun}}
      when 1
        "1 #{{{noun}}}"
      else
        "#{{{count}}} #{Ktistec::Util.pluralize({{noun}})}"
      end
    end

    # Emits a comma when one would be necessary when iterating through
    # a collection.
    #
    macro comma(collection, counter)
      {{counter}} < {{collection}}.size - 1 ? "," : ""
    end

    # Generates a random, URL-safe identifier.
    #
    macro id
      Ktistec::Util.id
    end
  end
end
