# ScreenPeek 🖥️🔍

**ScreenPeek** là ứng dụng thuần macOS (viết bằng Swift + `ScreenCaptureKit`) hiển thị trực tiếp nội dung của **màn hình kết nối (External Display / Máy chiếu)** trong một cửa sổ nổi chuẩn thiết kế Apple dễ dàng co dãn ngay trên màn hình máy tính chính.

Ứng dụng được thiết kế chuyên biệt cho bối cảnh **thuyết trình, hội thảo, giảng dạy**: khi bạn đứng song song hoặc quay lưng với màn hình máy chiếu lớn ở chế độ *Extended Display*, bạn không cần phải ngoái cổ nhìn màn hình phụ mà vẫn quan sát rõ chữ nhỏ, vị trí chuột, chiếu đèn Laser cho khán giả và điều khiển mượt mà ngay trên màn hình laptop.

---

## 📸 Hình ảnh giao diện chuẩn macOS (v1.3.1)

### 1. Bố cục mới (Dark Mode): Biểu tượng kèm Trích dẫn, Phím tắt & Nút chọn Khởi động nhanh + Kính lúp `2.8×`
![ScreenPeek Live View](docs/screenshots/screenpeek-live-view.png)

### 2. Chế độ Điều khiển trực tiếp (`Interactive`), Nhãn báo cập nhật mới & Ghi chú tính năng kính mờ (`Instant Tooltip`)
![ScreenPeek Interactive Mode & Instant Tooltip](docs/screenshots/screenpeek-interactive-tooltip.png)

### 3. Cửa sổ Cài đặt chuẩn macOS System Settings & Tự động cập nhật trực tiếp qua GitHub Releases
![ScreenPeek macOS Settings & GitHub Update](docs/screenshots/screenpeek-settings.png)

---

## ✨ Tính năng nổi bật (v1.3.1)

1. **Thanh công cụ trực quan & Tùy chọn Khởi động nhanh ngay trên bảng chính**:
   - **Bố cục chuẩn macOS**: Tầng 1 tích hợp nút cửa sổ (`🔴 🟡 🟢`), chọn màn hình, chuyển chế độ (`⌃⌥I`) và Cài đặt (`⌘,`). Tầng 2 dàn đều 7 ô tác vụ rõ ràng gồm **Icon + Tên tính năng ở trên** và **Phím tắt tương ứng ở ngay phía dưới**.
   - **Thanh nút chọn khởi động trực tiếp**: Tích chọn ngay trên bảng chính **`☑ Khởi động cùng macOS`**, **`☑ Bật bảng này khi khởi động`** (hoặc bỏ chọn để chạy ngầm `0% CPU/Pin` trên thanh Menu Bar cho đến khi nhấn `⌃⌥M`), và **`☑ Ẩn trên thanh Dock`**.
   - **Thanh trạng thái HUD nổi kiểu QuickTime**: Tự động ẩn mượt mà khi chuột rời cửa sổ để hiển thị trọn vẹn 100% khung hình màn hình phụ, tự hiện lại khi rê chuột vào.
   - **Cửa sổ Cài đặt chuẩn `macOS System Settings` (`⌘,`)**: Bố cục Sidebar kính mờ kèm biểu tượng màu đặc trưng của Apple và thẻ `Grouped Form`.
2. **Tự động kiểm tra & Cập nhật trực tiếp qua GitHub (`In-App GitHub Updater`)**:
   - Tự động kiểm tra bản phát hành mới từ **GitHub Releases** (`hungmtuci/ScreenPeek`) khi khởi động hoặc theo yêu cầu.
   - Xem trực tiếp **Ghi chú phát hành (*Release Notes*)**, tải gói cập nhật với thanh tiến trình thời gian thực, tự động giải nén, gỡ cách ly Gatekeeper, thay thế ứng dụng và **tự khởi động lại chỉ với 1 cú nhấp chuột**.
3. **Truyền hình trực tiếp 60 FPS & Tối ưu pin động (`Dynamic Stream Scaling`)**:
   - Kết xuất trực tiếp qua `IOSurface` (zero-copy GPU). Tự động co dãn độ phân giải thu hình theo kích thước cửa sổ thực tế và tự dừng bộ đếm nền khi tạm dừng để tiết kiệm pin.
   - Tự động loại trừ tất cả cửa sổ của `ScreenPeek` để không bao giờ bị lặp hình vô tận (*infinite mirror*).
4. **Kính lúp phóng đại vùng quanh chuột (`Cursor Zoom Loupe`)**:
   - Phóng đại sắc nét `1.8x – 4.5x` vùng chữ và nút bấm ngay dưới mũi chuột (chế độ *Giữ phím `⌥ Option`* hoặc *Luôn bật*).
5. **Đèn Laser / Spotlight & Màn che bảo mật máy chiếu (`Privacy Blackout`)**:
   - Chiếu tia **Laser Đỏ** hoặc **Spotlight sân khấu** trực tiếp lên màn hình máy chiếu thật cho khán giả.
   - Phủ màn hình chờ lịch sự lên máy chiếu với khán giả trong khi bạn **vẫn nhìn thấy và thao tác riêng tư bình thường** ngay trong cửa sổ `ScreenPeek`.
6. **2 chế độ tương tác chuột linh hoạt**:
   - **👁 Chỉ xem (`Live View`)**: Di chuột thật sang màn hình phụ và quan sát qua cửa sổ nhỏ. Nhấp đúp vào hình để nhảy nhanh chuột sang vị trí đó.
   - **🖱 Điều khiển trực tiếp (`Interactive`)**: Click trái/phải, nhấp đúp, kéo thả hoặc cuộn trang ngay trong cửa sổ nhỏ.

---

## ⌨️ Phím tắt toàn cục & Ứng dụng

Mặc định sử dụng bộ phím **`⌃⌥` (`Control + Option`)** (có thể đổi trong `Cài đặt › Phím tắt`):

| Phím tắt | Chức năng |
| :--- | :--- |
| `⌃⌥M` | Hiện / Ẩn nhanh cửa sổ **ScreenPeek** |
| `⌃⌥S` | **Tạm dừng / Tiếp tục** thu hình màn hình |
| `⌃⌥C` | **Nhảy nhanh chuột qua lại giữa 2 màn hình** (chính ↔ phụ) |
| `⌃⌥Z` | Chuyển chế độ **Kính lúp phóng đại** (hoặc giữ phím `⌥`) |
| `⌃⌥I` | Đổi nhanh giữa chế độ **Chỉ xem** và **Điều khiển trực tiếp** |
| `⌃⌥L` | Bật / Tắt **Đèn Laser / Spotlight** cho khán giả trên màn hình chiếu |
| `⌃⌥B` | Bật / Tắt **Màn che bảo mật (Blackout)** trên màn hình chiếu |
| `⌃⌥T` | Bật / Tắt **Chế độ Xuyên chuột (Click-Through)** |
| `⌃⌥P` | Bật / Tắt **Ghim cửa sổ luôn nổi (Always on Top)** |
| `⌃⌥H` | Bật / Tắt **Giao diện tràn viền tự ẩn (PiP)** |
| `⌘,` | Mở cửa sổ **Cài đặt & Cập nhật phần mềm** |

---

## 📥 Cài đặt & Cập nhật

### Cách 1: Tải bản đóng gói sẵn (Releases) & Tự động cập nhật
1. Tải file **`ScreenPeek.zip`** tại mục [**Releases**](../../releases/latest).
2. Giải nén và kéo **`ScreenPeek.app`** vào thư mục `/Applications` (hoặc chạy trực tiếp).
3. Lần đầu mở ứng dụng, nếu macOS hỏi xác thực, chạy lệnh gỡ cách ly:
   ```bash
   xattr -cr /Applications/ScreenPeek.app
   ```
4. Từ các phiên bản tiếp theo, bạn chỉ cần mở **`Cài đặt (⌘,) › Cập nhật`** và nhấn **"Cập nhật & Khởi động lại ngay"** để nâng cấp trực tiếp từ GitHub!

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
├── scripts/
│   └── generate_icon.swift                 # Tự động vẽ & đóng gói biểu tượng chuẩn macOS AppIcon.icns
└── Sources/ScreenPeek/
    ├── ScreenPeekApp.swift                 # AppDelegate, Menu Bar SF Symbols, Hotkeys & Cửa sổ
    ├── Models/
    │   └── DisplayInfo.swift               # Model màn hình, Tab cài đặt, Phím tắt & UI
    ├── Services/
    │   ├── ScreenCaptureManager.swift      # Thu hình ScreenCaptureKit + Dynamic Scaling tiết kiệm pin
    │   ├── CursorAndInputController.swift  # Theo dõi chuột thông minh & điều khiển từ xa CGEvent
    │   ├── ProjectorOverlayManager.swift   # Cửa sổ Đèn Laser / Spotlight & Màn che Blackout
    │   └── GitHubUpdateManager.swift       # Kiểm tra, tải về & tự cài đặt bản cập nhật từ GitHub Releases
    └── UI/
        ├── PreviewWindowView.swift         # Thanh tiêu đề kính mờ đồng nhất & HUD nổi kiểu QuickTime
        ├── SettingsWindowView.swift        # Cửa sổ Cài đặt chuẩn macOS System Settings & Cập nhật
        ├── MacVisualComponents.swift       # Thành phần giao diện macOS (Keycaps, Icon Badges, DragArea)
        └── VideoSurfaceView.swift          # Lớp hiển thị CALayer + Kính lúp GPU IOSurface
```

## 📄 Giấy phép

Phát hành theo giấy phép [MIT License](LICENSE).
