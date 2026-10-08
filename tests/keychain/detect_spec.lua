local detect = require("keychain.detect")
local env = require("keychain.env")
local config_mod = require("keychain.config")

describe("keychain.detect", function()
  describe("shannon_entropy", function()
    it("is zero for a single repeated character", function()
      assert.are.equal(0, detect.shannon_entropy("aaaaaa"))
    end)

    it("is 1 bit/char for a balanced two-symbol string", function()
      assert.is_true(math.abs(detect.shannon_entropy("abab") - 1) < 1e-9)
    end)

    it("is 0 for the empty string", function()
      assert.are.equal(0, detect.shannon_entropy(""))
    end)
  end)

  describe("key_matches", function()
    local patterns = config_mod.defaults.detection.key_patterns

    it("matches common secret-ish key names", function()
      assert.is_true(detect.key_matches("API_KEY", patterns))
      assert.is_true(detect.key_matches("DATABASE_PASSWORD", patterns))
      assert.is_true(detect.key_matches("AWS_SECRET_ACCESS_KEY", patterns))
      assert.is_true(detect.key_matches("STRIPE_TOKEN", patterns))
    end)

    it("does not match ordinary config keys", function()
      assert.is_false(detect.key_matches("DEBUG", patterns))
      assert.is_false(detect.key_matches("PORT", patterns))
      assert.is_false(detect.key_matches("LOG_LEVEL", patterns))
    end)
  end)

  describe("is_plaintext_secret", function()
    local config = config_mod.build()

    local function entry_for(line)
      return env.parse_line(line, 1)
    end

    it("does not flag ordinary values", function()
      assert.is_false(detect.is_plaintext_secret(entry_for("DEBUG=true"), config))
      assert.is_false(detect.is_plaintext_secret(entry_for("PORT=3000"), config))
    end)

    it("does not flag existing keychain references", function()
      assert.is_false(detect.is_plaintext_secret(entry_for("API_KEY=keychain://API_KEY"), config))
    end)

    it("does not flag placeholder values", function()
      assert.is_false(detect.is_plaintext_secret(entry_for("API_KEY=changeme"), config))
      assert.is_false(detect.is_plaintext_secret(entry_for("API_KEY="), config))
    end)

    it("flags a secret-ish key with a real-looking value", function()
      local flagged, reason = detect.is_plaintext_secret(
        entry_for("API_KEY=sk_test_abcdefghijklmnopqrstuvwxyz123456"),
        config
      )
      assert.is_true(flagged)
      assert.is_string(reason)
    end)

    it("flags a high-entropy value even under a generic key name", function()
      local flagged = detect.is_plaintext_secret(
        entry_for("SOME_VALUE=aG9yc2ViYXR0ZXJ5c3RhcGxlY29ycmVjdGhvcnNlMTIzNDU2"),
        config
      )
      assert.is_true(flagged)
    end)
  end)

  describe("scan", function()
    it("returns one entry per flagged line", function()
      local entries = env.parse_lines({
        "DEBUG=true",
        "API_KEY=sk_test_abcdefghijklmnopqrstuvwxyz123456",
        "DATABASE_PASSWORD=changeme",
      })
      local flagged = detect.scan(entries, config_mod.build())
      assert.are.equal(1, #flagged)
      assert.are.equal("API_KEY", flagged[1].entry.key)
    end)
  end)
end)
