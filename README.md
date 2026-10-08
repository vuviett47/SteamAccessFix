<h1 align="center">SteamAccessFix (SAF)</h1>

<p align="center">Công cụ mã nguồn mở dạng tập tin đơn (.cmd) giúp tự động khắc phục sự cố kết nối và mở khóa Steam (Store, Community, CDN hình ảnh/tài nguyên) trên Windows 10 và 11.</p>

<p align="center">
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-blue?logo=windows" alt="Windows Support">
  <img src="https://img.shields.io/badge/Driver-Zero%20Dependency-brightgreen" alt="No Drivers">
  <img src="https://img.shields.io/badge/Anti--Cheat-Safe-success" alt="Anti-Cheat Safe">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey" alt="License">
</p>

<hr>

## Cách sử dụng

### Cách 1 - Chạy nhanh qua PowerShell

1. Mở **Start Menu**, tìm `PowerShell` (hoặc `Terminal`) và mở lên.
2. Dán đoạn mã bên dưới và nhấn **Enter**:

   ```powershell
   irm https://raw.githubusercontent.com/vuviett47/SteamAccessFix/main/SteamAccessFix.cmd | iex
   ```

   *Nếu lệnh trên bị chặn do DNS, hãy dùng lệnh sau (tự động dùng DoH Cloudflare):*
   ```powershell
   iex (curl.exe -s --doh-url https://1.1.1.1/dns-query https://raw.githubusercontent.com/vuviett47/SteamAccessFix/main/SteamAccessFix.cmd | Out-String)
   ```

---

### Cách 2 - Tải file trực tiếp (Truyền thống)

1. Tải về file kịch bản:
   * [**SteamAccessFix.cmd**](https://raw.githubusercontent.com/vuviett47/SteamAccessFix/main/SteamAccessFix.cmd) *(Nhấp chuột phải chọn Lưu liên kết dưới dạng... / Save link as...)*
2. Nhấp đúp chuột hoặc nhấp chuột phải chọn **Run as administrator** vào file `SteamAccessFix.cmd`.
3. Công cụ sẽ tự động phát hiện tình trạng mạng và kích hoạt phương pháp tối ưu nhất.

---

## Các cấp độ hoạt động (Progressive Detection)

Công cụ tuân theo nguyên tắc **thử từ nhẹ đến nâng cao** và **dừng ngay khi kết nối thành công**:

| Cấp độ | Phương pháp | Cơ chế kỹ thuật |
| :--- | :--- | :--- |
| **Level 0** | **Kiểm tra ban đầu** | Kiểm tra kết nối tới máy chủ Steam. Nếu mạng đã vào được bình thường, công cụ dừng lại ngay và không thay đổi bất kỳ cài đặt nào. |
| **Level 1** | **DNS Google** | Gán DNS Google (`8.8.8.8` & IPv6 `2001:4860:4860::8888`), xóa cache DNS để chặn triệt để tình trạng DNS poisoning từ modem/nhà mạng. |
| **Level 2** | **SplitProxy (SNI)** | Khởi chạy proxy nội bộ (C# nhúng sẵn). Phân mảnh gói tin TLS `ClientHello` (cắt đôi chuỗi tên miền SNI) để vô hiệu hóa bộ lọc DPI bắt gói tin. |
| **Level 3** | **DoH Fallback** | Truy vấn IP máy chủ gốc trực tiếp từ Cloudflare/Google qua DNS-over-HTTPS, hỗ trợ gán tạm thời vào file hosts nếu cần. |

---

## Điểm vượt trội về an toàn

* **100% User-Mode (Không Driver)**: Hoàn toàn không cài đặt dịch vụ nền hay driver kernel (`WinDivert`). An toàn 100%, không bao giờ bị các hệ thống chống gian lận (Vanguard, Easy Anti-Cheat, BattlEye, FACEIT) cảnh báo hay khóa tài khoản.
* **Định tuyến chọn lọc (Selective Routing)**: Tự động tạo tệp cấu hình Proxy Auto-Configuration (PAC). Chỉ lưu lượng truy cập của riêng Steam mới đi qua proxy; các trò chơi khác, trình duyệt và kết nối mạng thông thường hoàn toàn đi thẳng với tốc độ tối đa.
* **Tự động khôi phục hoàn toàn**: Khi bạn nhấn `Enter` để đóng script, toàn bộ DNS, cài đặt Proxy và file hosts sẽ được trả về trạng thái nguyên bản trước khi chạy. Có cơ chế tự dọn dẹp nếu người dùng vô tình bấm tắt dấu X.
* **Tự động cập nhật**: Tích hợp sẵn cơ chế kiểm tra phiên bản mới từ GitHub và tự động cập nhật an toàn chỉ với 1 phím bấm.

---

> [!TIP]
> - **Hãy giữ cửa sổ console mở** trong suốt quá trình chơi game hoặc duyệt Steam nếu công cụ đang hoạt động ở chế độ `Level 2 (SplitProxy)`.
> - **Phím tắt điều khiển khi đang chạy:**
>   - Gõ `T` + Enter: Kiểm tra lại tốc độ và trạng thái kết nối tới Steam.
>   - Gõ `K` + Enter: Giữ lại thiết lập DNS Google trên máy và thoát chương trình.
>   - Nhấn `Enter`: **Khôi phục toàn bộ cài đặt mạng ban đầu** và thoát an toàn.

> [!NOTE]
> - Lệnh `irm` trong PowerShell dùng để tải mã nguồn từ liên kết, và `iex` sẽ thực thi mã đó trong bộ nhớ.
> - Bạn có thể xem toàn bộ mã nguồn công khai trực tiếp tại file [`SteamAccessFix.cmd`](SteamAccessFix.cmd).

---

<p align="center">
  <b>Phiên bản hiện tại:</b> 1.0.0 &bull; <b>Tác giả:</b> <a href="https://github.com/vuviett47">vuviett47</a>
</p>
