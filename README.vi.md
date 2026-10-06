# macism-ime.nvim (Tiếng Việt)

Tự động chuyển bộ gõ trên macOS theo mode của Neovim, dựa trên [macism](https://github.com/laishulu/macism).
Làm cho người gõ tiếng Việt (XKey, v.v.), nhưng dùng được với mọi input source ID.

- **Normal / Visual / `:`** → ABC
- **Insert / Replace / Select / Terminal** → input bạn dùng lần trước
- **`/`, `?` và `:%s/…`** → input của Insert, để tìm kiếm và thay thế bằng tiếng Việt
- **Mở nvim** → lưu input hiện tại; **thoát** (và `Ctrl-Z`) → trả lại
- Tùy chọn: nhớ theo buffer, ép input theo filetype, nhận diện chữ Việt quanh con trỏ
- Chỉ chạy trên macOS; hệ khác `setup()` không làm gì nên dotfiles dùng chung vẫn an toàn.

## Cài đặt

Cần macOS, Neovim 0.10+ và macism: `brew install laishulu/homebrew/macism`.
Muốn biết ID của một bộ gõ, hãy chuyển sang bộ gõ đó rồi chạy `macism` trong terminal.

lazy.nvim:

```lua
{
  "drnhat/macism-ime.nvim",
  lazy = false,
  config = function()
    require("macism_ime").setup({
      scope = "buffer",
      detect = { enable = true, input = "com.codetay.inputmethod.XKey" },
    })
  end,
}
```

Danh sách đầy đủ các tùy chọn nằm trong [README.md](README.md#configuration).
Lệnh: `:MacismImeToggle`, `:MacismImeInfo`.

Mất phím đầu sau khi bấm `i`: chạy `brew upgrade macism` hoặc đặt `wait = 150`.
Bật `debug = true` rồi xem `~/.local/state/nvim/ime.log` để biết chi tiết.

## Giấy phép

MIT
