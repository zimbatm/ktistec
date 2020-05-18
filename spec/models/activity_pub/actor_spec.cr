require "../../spec_helper"

class FooBarActor < ActivityPub::Actor
end

Spectator.describe ActivityPub::Actor do
  before_each { Balloon.database.exec "BEGIN TRANSACTION" }
  after_each { Balloon.database.exec "ROLLBACK" }

  let(username) { random_string }
  let(password) { random_string }

  let(foo_bar) do
    FooBarActor.new(
      aid: "https://test.test/#{random_string}",
      pem_public_key: (<<-KEY
        -----BEGIN PUBLIC KEY-----
        MFowDQYJKoZIhvcNAQEBBQADSQAwRgJBAKr1/30vwtQozUzKAiM87+cJzUvA15KR
        KNFcMekDexfrLUk8EjP0psKcm9AGVefYvfKtD2cAGhF6UTZKVUUZRmECARE=
        -----END PUBLIC KEY-----
        KEY
      ),
      pem_private_key: (<<-KEY
        -----BEGIN PRIVATE KEY-----
        MIIBUQIBADANBgkqhkiG9w0BAQEFAASCATswggE3AgEAAkEAqvX/fS/C1CjNTMoC
        Izzv5wnNS8DXkpEo0Vwx6QN7F+stSTwSM/Smwpyb0AZV59i98q0PZwAaEXpRNkpV
        RRlGYQIBEQJAHitpUlO4+ENvhgWH6BnP+5hRZ7ieg0bK98T5v7VR9Sk2e/9cHRsj
        kEztFNLNvWRiib1JWyP3f8uXbmnLsTQtMQIhAN6PLZn4nssJ0j2pv5jnhYKInq/g
        Y85JWNP0s0K8c/15AiEAxKYSGOu8EjHBHrBG2c8aYl2IaoIl0UlKeHqU5Zx9nikC
        IFukXhI5MlOaod0nx10UCcxWX3WYoZEtQrGg/oTkL8K5AiAXIpi3o0NNb0PlfiZz
        +j9W3dPQS4v6gRfR8E3AqP+4QQIgEnP6htV+XMD4H9zg9aG+GFDorjWctnpNR6Z7
        +4EIKbQ=
        -----END PRIVATE KEY-----
        KEY
      )
    ).save
  end

  describe "#public_key" do
    it "returns the public key" do
      expect(foo_bar.public_key).to be_a(OpenSSL::RSA)
    end
  end

  describe "#private_key" do
    it "returns the private key" do
      expect(foo_bar.private_key).to be_a(OpenSSL::RSA)
    end
  end

  context "when using the keypair" do
    it "verifies the signed message" do
      message = "this is a test"
      private_key = foo_bar.private_key
      public_key = foo_bar.public_key
      if private_key && public_key
        signature = private_key.sign(OpenSSL::Digest.new("SHA256"), message)
        expect(public_key.verify(OpenSSL::Digest.new("SHA256"), signature, message)).to be_true
      end
    end
  end

  context "when validating" do
    let!(actor) { described_class.new(aid: "http://test.test/foo_bar").save }

    it "must be present" do
      expect(described_class.new.valid?).to be_false
    end

    it "must be an absolute URI" do
      expect(described_class.new(aid: "/some_actor").valid?).to be_false
    end

    it "must be unique" do
      expect(described_class.new(aid: "http://test.test/foo_bar").valid?).to be_false
    end

    it "is valid" do
      expect(described_class.new(aid: "http://test.test/#{random_string}").save.valid?).to be_true
    end
  end

  let(json) do
    <<-JSON
      {
        "@context":[
          "https://www.w3.org/ns/activitystreams",
          "https://w3id.org/security/v1"
        ],
        "@id":"https://test.test/foo_bar",
        "@type":"FooBarActor",
        "preferredUsername":"foo_bar",
        "publicKey":{
          "id":"https://test.test/foo_bar#public-key",
          "owner":"https://test.test/foo_bar",
          "publicKeyPem":"---PEM PUBLIC KEY---"
        },
        "privateKey":{
          "id":"https://test.test/foo_bar#private-key",
          "owner":"https://test.test/foo_bar",
          "privateKeyPem":"---PEM PRIVATE KEY---"
        },
        "inbox": "inbox link",
        "outbox": "outbox link",
        "following": "following link",
        "followers": "followers link",
        "name":"Foo Bar",
        "summary": "<p></p>",
        "icon": {
          "type": "Image",
          "mediaType": "image/jpeg",
          "url": "icon link"
        },
        "image": {
          "type": "Image",
          "mediaType": "image/jpeg",
          "url": "image link"
        }
      }
    JSON
  end

  describe ".from_json_ld" do
    it "creates a new instance" do
      actor = described_class.from_json_ld(json).save.as_a(FooBarActor)
      expect(actor.aid).to eq("https://test.test/foo_bar")
      expect(actor.username).to eq("foo_bar")
      expect(actor.pem_public_key).to eq("---PEM PUBLIC KEY---")
      expect(actor.pem_private_key).to eq("---PEM PRIVATE KEY---")
      expect(actor.inbox).to eq("inbox link")
      expect(actor.outbox).to eq("outbox link")
      expect(actor.following).to eq("following link")
      expect(actor.followers).to eq("followers link")
      expect(actor.name).to eq("Foo Bar")
      expect(actor.summary).to eq("<p></p>")
      expect(actor.icon).to eq("icon link")
      expect(actor.image).to eq("image link")
    end
  end

  describe "#from_json_ld" do
    it "updates an existing instance" do
      actor = described_class.new.from_json_ld(json).save
      expect(actor.aid).to eq("https://test.test/foo_bar")
      expect(actor.username).to eq("foo_bar")
      expect(actor.pem_public_key).to eq("---PEM PUBLIC KEY---")
      expect(actor.pem_private_key).to eq("---PEM PRIVATE KEY---")
      expect(actor.inbox).to eq("inbox link")
      expect(actor.outbox).to eq("outbox link")
      expect(actor.following).to eq("following link")
      expect(actor.followers).to eq("followers link")
      expect(actor.name).to eq("Foo Bar")
      expect(actor.summary).to eq("<p></p>")
      expect(actor.icon).to eq("icon link")
      expect(actor.image).to eq("image link")
    end
  end
end