# ScreenPeek 🖥️🔍

**ScreenPeek** là ứng dụng macOS gọn nhẹ (viết bằng Swift + `ScreenCaptureKit`) hiển thị trực tiếp nội dung của **màn hình kết nối (External Display / Máy chiếu)** trong một cửa sổ nổi có thể co dãn ngay trên màn hình máy tính chính.

Ứng dụng được thiết kế đặc biệt cho bối cảnh **thuyết trình, hội thảo, giảng dạy**: khi bạn đứng song song hoặc quay lưng với màn hình máy chiếu lớn ở chế độ *Extended Display*, bạn không cần phải ngoái cổ nhìn màn hình phụ mà vẫn quan sát rõ vị trí chuột và điều khiển mượt mà ngay trên màn hình laptop.

---

## 📸 Hình ảnh giao diện

### 1. Chế độ Chỉ xem (`Live View`) & Vòng sáng làm nổi bật vị trí chuột
![ScreenPeek Live View](docs/screenshots/screenpeek-live-view.png)

### 2. Chế độ Điều khiển trực tiếp (`Interactive`) & Ghi chú tính năng tức thì (`Instant Tooltip`)
![ScreenPeek Interactive Mode & Instant Tooltip](docs/screenshots/screenpeek-interactive-tooltip.png)

### 3. Tuỳ chỉnh Vòng sáng con trỏ, Độ trong suốt & Ẩn biểu tượng trên thanh Dock
![ScreenPeek Settings](docs/screenshots/screenpeek-settings.png)

---

## ✨ Tính năng nổi bật

- **Truyền hình trực tiếp 60 FPS (Zero-Copy `IOSurface`)**: Độ trễ cực thấp, tối ưu GPU/CPU qua `ScreenCaptureKit`. Tự động nhận diện và ưu tiên màn hình phụ ngay khi cắm cáp HDMI / USB-C, đồng thời loại trừ chính cửa sổ `ScreenPeek` để không bao giờ bị lặp hình vô tận (*infinite mirror*).
- **2 chế độ tương tác linh hoạt**:
  - **👁 Chỉ xem (`Live View`)**: Bạn di chuột thật trên màn hình phụ và quan sát qua cửa sổ thu nhỏ. **Nhấp đúp (Double-click)** vào điểm bất kỳ trên hình để nhảy nhanh chuột thật sang đúng vị trí đó trên màn hình phụ.
  - **🖱 Điều khiển trực tiếp (`Interactive`)**: Click trái, click phải, nhấp đúp, kéo thả (*drag*) hoặc cuộn chuột (*scroll*) ngay bên trong cửa sổ nhỏ để thao tác từ xa lên màn hình phụ (hỗ trợ tự động giữ con trỏ chuột ở lại cửa sổ nhỏ sau khi click).
- **Vòng tròn làm nổi bật con trỏ (`Cursor Highlight`)**: Hiển thị vòng phát sáng độ tương phản cao quanh vị trí chuột trên màn hình phụ (tuỳ chỉnh màu *Vàng nổi bật, Đỏ Laser, Xanh Cyan, Xanh Neon* và kích thước vòng sáng), giúp dễ nhìn ngay cả khi cửa sổ thu nhỏ.
- **Khóa tỷ lệ khung hình (`Aspect Ratio Lock`)**: Co dãn cửa sổ giữ chuẩn tỷ lệ của màn hình phụ hoặc tắt để co dãn tự do.
- **Luôn nổi trên cùng (`Always on Top`) & Ẩn khỏi thanh Dock**: Ghim cửa sổ nổi trên mọi ứng dụng/Spaces và tuỳ chọn ẩn biểu tượng khỏi thanh Dock để gọn gàng khi trình chiếu.
- **Hộp ghi chú tính năng tức thì (`Instant Tooltip`)**: Hiển thị giải thích chi tiết ngay khi rê chuột lên các biểu tượng điều khiển.

---

## ⌨️ Phím tắt toàn cục (Global Hotkeys)

| Phím tắt | Chức năng |
| :--- | :--- |
| `⌘⇧M` (`Command + Shift + M`) | Hiện / Ẩn nhanh cửa sổ **ScreenPeek** |
| `⌘⇧C` (`Command + Shift + C`) | **Chuyển nhanh chuột qua lại giữa 2 màn hình** (từ màn hình chính sang màn hình phụ và ngược lại) |
| `⌘⇧I` (`Command + Shift + I`) | Đổi nhanh giữa chế độ **Chỉ xem** và **Điều khiển trực tiếp** |

---

## 📥 Cài đặt & Sử dụng

### Cách 1: Tải bản đóng gói sẵn (Releases)
1. Tải file **`ScreenPeek.zip`** tại mục [**Releases**](../../releases/latest).
2. Giải nén và kéo **`ScreenPeek.app`** vào thư mục `/Applications` (hoặc chạy trực tiếp).
3. Nếu macOS báo ứng dụng chưa xác thực Apple Developer ID, mở Terminal chạy lệnh gỡ cách ly:
   ```bash
   xattr -cr /Applications/ScreenPeek.app
   ```
4. Cấp quyền lần đầu trong **System Settings > Privacy & Security**:
   - **Screen & System Audio Recording (Ghi màn hình)**: Bắt buộc để hiển thị nội dung màn hình kết nối.
   - **Accessibility (Trợ năng)**: Tuỳ chọn — chỉ cần nếu bạn dùng chế độ *Điều khiển trực tiếp (`Interactive`)* để gửi thao tác click/cuộn chuột từ xa.

### Cách 2: Tự biên dịch từ mã nguồn (macOS 14.0+)
```bash
git clone https://github.com/hungmtuci/ScreenPeek.git
cd ScreenPeek
chmod +x build_screenpeek.sh
./build_screenpeek.sh
open ScreenPeek.app
```

---

## 🗂️ Cấu trúc dự án

```text
ScreenPeek/
├── Package.swift
├── build_screenpeek.sh
└── Sources/ScreenPeek/
    ├── ScreenPeekApp.swift                 # AppDelegate, Menu Bar, Hotkeys, Aspect Ratio Resize
    ├── Models/
    │   └── DisplayInfo.swift               # Model màn hình, chế độ tương tác & cấu hình UI
    ├── Services/
    │   ├── ScreenCaptureManager.swift      # Thu hình 60 FPS qua ScreenCaptureKit + IOSurface
    │   └── CursorAndInputController.swift  # Theo dõi tọa độ chuột & điều khiển từ xa qua CGEvent
    └── UI/
        ├── PreviewWindowView.swift         # Thanh công cụ, Instant Tooltips & Cursor Highlight
        └── VideoSurfaceView.swift          # Lớp hiển thị CALayer & xử lý sự kiện chuột
```

## 📄 Giấy phép

Phát hành theo giấy phép [MIT License](LICENSE).
