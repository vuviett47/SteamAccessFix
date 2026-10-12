<h1 align="center">SteamAccessFix (SAF)</h1>

<p align="center">Công cụ mã nguồn mở dạng tập tin đơn (.cmd) giúp tự động khắc phục sự cố kết nối, mở khóa Steam (Store, Community, CDN), sửa lỗi màn hình đen / màn khói PUBG, hỗ trợ định tuyến Naraka & Delta Force, và tối ưu ping cho game thủ trên Windows 10 và 11.</p>

<p align="center">
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-blue?logo=windows" alt="Windows Support">
  <img src="https://img.shields.io/badge/Driver-Zero%20Dependency-brightgreen" alt="No Drivers">
  <img src="https://img.shields.io/badge/Anti--Cheat-100%25%20Safe-success" alt="Anti-Cheat Safe">
  <img src="https://img.shields.io/badge/Version-1.1.2-orange" alt="Version 1.1.2">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey" alt="License">
</p>

<hr>

## Tính năng chính (v1.1.2)

- **Mở khóa toàn diện Steam**: Khắc phục lỗi không tải được Steam Store, Community, hồ sơ người chơi, hình ảnh, CDN tải game và Steam Web API.
- **Hỗ trợ tối ưu CS2 & Dota 2**: Đảm bảo tải mượt mà CS2 / Dota 2 blog, cập nhật, cộng đồng, Steam API Game Coordinator (GC); lưu lượng trận đấu SDR UDP đi trực tiếp 100%.
- **Sửa triệt để lỗi PUBG**: Xử lý tình trạng màn hình đen, màn hình khói vô tận khi khởi động PUBG tại sảnh chờ (lobby) do nhà mạng FPT, VNPT chặn tên miền Chromium/CEF.
- **Hỗ trợ định tuyến Naraka: Bladepoint & Delta Force**: Đảm bảo kết nối thông suốt đến các dịch vụ máy chủ và API sự kiện của game.
- **Tối ưu độ trễ và Ping Windows**: Tự động tinh chỉnh network stack Windows (`NetworkThrottlingIndex`, `SystemResponsiveness`, TCP AutoTuning) nhằm loại bỏ độ trễ và nghẽn băng thông khi chơi game.
- **100% Anti-Cheat Safe**: Hoạt động hoàn toàn ở chế độ người dùng (User-Mode), không cài driver kernel (`WinDivert`, GoodbyeDPI), an toàn tuyệt đối với BattlEye, Easy Anti-Cheat, Vanguard, VAC, ACE.

---

## Cách sử dụng

### Cách 1 - Chạy nhanh qua PowerShell (Khuyên dùng)

1. Mở **Start Menu**, tìm `PowerShell` (hoặc `Terminal`) và mở lên.
2. Dán đoạn mã bên dưới và nhấn **Enter**:

   ```powershell
   irm https://raw.githubusercontent.com/vuviett47/SteamAccessFix/main/SteamAccessFix.cmd | iex
   ```

   *Nếu lệnh trên bị chặn do DNS của nhà mạng, hãy dùng lệnh sau (tự động dùng DoH Cloudflare để tải):*
   ```powershell
   iex (curl.exe -s --doh-url https://1.1.1.1/dns-query https://raw.githubusercontent.com/vuviett47/SteamAccessFix/main/SteamAccessFix.cmd | Out-String)
   ```

---

### Cách 2 - Tải file trực tiếp (Truyền thống)

1. Tải về file kịch bản:
   * [**SteamAccessFix.cmd**](https://raw.githubusercontent.com/vuviett47/SteamAccessFix/main/SteamAccessFix.cmd) *(Nhấp chuột phải chọn Lưu liên kết dưới dạng... / Save link as...)*
2. Nhấp đúp chuột hoặc nhấp chuột phải chọn **Run as administrator** vào file `SteamAccessFix.cmd`.
3. Công cụ sẽ tự động phát hiện tình trạng mạng, áp dụng các tinh chỉnh và kích hoạt chế độ tối ưu nhất.

---

## Các cấp độ hoạt động (Progressive Detection)

Công cụ tuân theo nguyên tắc **thử từ nhẹ đến nâng cao** và **dừng ngay khi kết nối thành công**:

| Cấp độ | Phương pháp | Cơ chế kỹ thuật |
| :--- | :--- | :--- |
| **Level 0** | **Kiểm tra ban đầu** | Kiểm tra kết nối tới máy chủ Steam và PUBG. Nếu mạng đã hoạt động bình thường, công cụ chỉ áp dụng tinh chỉnh network giảm ping và không can thiệp sâu. |
| **Level 1** | **DNS Google + IPv6** | Gán DNS Google (`8.8.8.8` & IPv6 `2001:4860:4860::8888`), xóa cache DNS để chặn triệt để tình trạng DNS poisoning từ modem/nhà mạng. |
| **Level 2** | **SplitProxy (SNI Fragmentation)** | Khởi chạy proxy nội bộ (C# nhúng sẵn). Phân mảnh gói tin TLS `ClientHello` (chia tách SNI) để vô hiệu hóa tường lửa DPI của nhà mạng FPT/VNPT. |
| **Level 3** | **DoH Fallback** | Truy vấn IP máy chủ gốc trực tiếp từ Cloudflare/Google qua DNS-over-HTTPS, hỗ trợ gán tạm thời vào file hosts nếu cần. |

---

## Điểm vượt trội về an toàn và hiệu năng

- **Zero-Driver (Không Driver)**: Hoàn toàn không cài đặt driver can thiệp sâu vào kernel hệ thống. Không bao giờ kích hoạt cờ cảnh báo của bất kỳ phần mềm chống gian lận nào.
- **Chỉ Proxy Web, Match Game đi thẳng**: Tệp cấu hình Proxy PAC chỉ áp dụng cho danh sách tên miền sảnh chờ và web Steam/PUBG/Naraka. Toàn bộ lưu lượng gói tin trận đấu (UDP game match traffic) kết nối trực tiếp đến máy chủ game, đảm bảo 0 ms độ trễ phát sinh.
- **Tự động khôi phục hoàn toàn**: Khi bạn nhấn `Enter` để thoát, toàn bộ cấu hình DNS, PAC Proxy và Registry sẽ được hoàn trả về trạng thái nguyên bản trước khi chạy.
- **Tự phục hồi sau sự cố**: Nếu máy tính bị sập nguồn đột ngột hoặc người dùng tắt ngang cửa sổ, công cụ sẽ tự động phát hiện và dọn dẹp cấu hình dư thừa ở lần khởi động kế tiếp.

---

> [!TIP]
> - **Hãy giữ cửa sổ console mở** trong suốt quá trình chơi game hoặc duyệt Steam nếu công cụ đang chạy ở chế độ `Level 2 (SplitProxy)`.
> - **Phím tắt điều khiển linh hoạt:**
>   - Gõ `1` + Enter: **Chạy Cấp độ 1** (Google DNS + Tối ưu Ping, tắt Proxy).
>   - Gõ `2` + Enter: **Chạy Cấp độ 2** (SplitProxy SNI Fragmentation vượt chặn mạnh).
>   - Gõ `K` + Enter: **Giữ lại (Keep)** thiết lập DNS và tinh chỉnh network trên máy rồi thoát.
>   - Nhấn `Enter` hoặc `Q`: **Khôi phục toàn bộ cài đặt mạng ban đầu** và thoát an toàn.

---

<p align="center">
  <b>Phiên bản hiện tại:</b> 1.1.2 &bull; <b>Tác giả:</b> <a href="https://github.com/vuviett47">vuviett47</a>
</p>
