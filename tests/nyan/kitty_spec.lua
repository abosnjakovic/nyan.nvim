local kitty = require("nyan.kitty")

describe("kitty", function()
  describe("id_to_colour", function()
    it("converts image id 1 to correct hex", function()
      assert.equals("#000001", kitty.id_to_colour(1))
    end)

    it("converts image id 255 to correct hex", function()
      assert.equals("#0000ff", kitty.id_to_colour(255))
    end)

    it("converts larger image ids correctly", function()
      assert.equals("#010000", kitty.id_to_colour(65536))
    end)
  end)

  describe("base64_encode", function()
    it("encodes simple string correctly", function()
      -- "hello" in base64 is "aGVsbG8="
      local encoded = kitty.base64_encode("hello")
      assert.equals("aGVsbG8=", encoded)
    end)

    it("handles empty string", function()
      local encoded = kitty.base64_encode("")
      assert.equals("", encoded)
    end)
  end)

  describe("is_supported", function()
    it("returns boolean", function()
      local result = kitty.is_supported()
      assert.is_boolean(result)
    end)
  end)

end)
