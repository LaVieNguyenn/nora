# Nora

Dọn dẹp, phân tích và tối ưu máy Mac — từ terminal hoặc từ một app nhỏ trên
thanh menubar.

Nora gồm hai phần dùng chung một bộ máy:

- **CLI** (`nora`) — dọn cache, gỡ app kèm tàn dư, phân tích ổ đĩa, bảo trì hệ
  thống, xem chỉ số máy.
- **App menubar** — theo dõi CPU, RAM, ổ đĩa, mạng, nhiệt độ và pin thiết bị
  theo thời gian thực; bấm vào từng chỉ số để xem chi tiết. Cửa sổ chính bọc
  các lệnh dọn dẹp, phân tích và gỡ app trong giao diện đồ hoạ.

App không tự xoá gì cả — mọi thao tác đều gọi qua CLI, nên các lớp bảo vệ
đường dẫn và whitelist luôn được áp dụng như nhau.

## Cài đặt

Một lệnh, không cần clone, không cần cài sẵn thứ gì:

```bash
curl -fsSL https://raw.githubusercontent.com/LaVieNguyenn/nora/main/install.sh | bash
```

Lệnh này tải bản dựng sẵn, đối chiếu checksum, cài CLI vào `~/.nora`, đặt lệnh
`nora` (và alias ngắn `nr`) vào `~/.local/bin`, rồi chép app menubar vào
`/Applications/Nora.app`.

Yêu cầu duy nhất là macOS 14 trở lên. **Không cần Go, không cần Xcode**: cả hai
binary Go lẫn app Swift đều dựng sẵn ở dạng universal, chạy được trên cả Apple
Silicon lẫn Intel.

Muốn tự build thay vì tải — cần Go, và cần thêm Swift (Xcode Command Line
Tools) nếu muốn có app; thiếu Swift thì vẫn được CLI:

```bash
curl -fsSL https://raw.githubusercontent.com/LaVieNguyenn/nora/main/install.sh | bash -s -- --from-source
```

Vài tuỳ chọn khác: `--version V0.1.0` cài đúng một bản, `--prefix` và
`--bin-dir` đổi nơi cài. Biến môi trường `NORA_RELEASE_BASE` trỏ trình cài đặt
sang một nơi khác chứa tệp phát hành, cho máy không ra được GitHub.

Gỡ ra:

```bash
nora remove
```

## Dùng

```bash
nora                  # menu tương tác
nora clean --dry-run  # xem trước những gì sẽ dọn, không xoá gì
nora clean            # dọn thật
nora analyze          # duyệt ổ đĩa, tìm thư mục nặng
nora uninstall        # gỡ app kèm tàn dư
nora optimize         # bảo trì hệ thống
nora status           # bảng chỉ số máy
```

Mọi lệnh có tính phá huỷ đều hỗ trợ `--dry-run` để xem trước.

App menubar mở kèm hệ thống nếu bạn bật trong Cài đặt. Nếu thanh menubar hết
chỗ và biểu tượng không hiện, mở cửa sổ chính bằng:

```bash
open /Applications/Nora.app --args --window
```

## Đã đổi gì so với bản gốc

Nora bắt nguồn từ [Mole](https://github.com/tw93/Mole) của tw93 — một công cụ
bảo trì macOS rất tốt. Đây là bản fork cá nhân, **không có liên kết hay bảo trợ
nào từ dự án Mole**, và mang tên riêng theo đúng chính sách thương hiệu của họ.

Những thay đổi chính:

**Thêm app menubar.** Toàn bộ phần giao diện đồ hoạ là mới, không có trong bản
gốc.

**Tối ưu hiệu năng**, mỗi mục đều đo được:

| Chỗ sửa | Trước | Sau |
|---|---|---|
| Vòng chờ timeout (dùng ở 127 nơi) | 125 ms/lần | 11.9 ms/lần |
| `nora clean --dry-run` | 88 s | 56 s |
| Khởi động mỗi lệnh | 111 ms | 77 ms |
| Quét lại `~/Library` | 6.0 s | 0.1 s |

- macOS không có `timeout(1)`, nên mọi lệnh có giới hạn thời gian đều đi qua
  một vòng chờ Perl ngủ cố định 0.1 giây — làm tròn mọi lệnh ngắn lên 100 ms.
  Đổi sang chờ ngắn dần.
- Entrypoint nạp toàn bộ thư viện rồi mới `exec` sang lệnh con, mà lệnh con lại
  nạp đúng bộ đó lần nữa. Giờ phân luồng trước khi nạp.
- Bốn cache trong `status` có thời hạn sống **bằng đúng** chu kỳ gọi chúng, nên
  chưa lần nào trúng; mỗi chu kỳ đều gọi lại `system_profiler`.
- Các thư mục nặng nhất (`node_modules`, `.git`, `Caches`, `DerivedData`) là
  thứ duy nhất không đi qua lớp cache của trình phân tích.
- Dọn Launch Services gọi `lsregister` tuần tự cho từng app; gộp lại một lệnh.

**Sửa lỗi**: `pmset` là tiến trình con duy nhất không có giới hạn thời gian —
nếu nó treo thì cả vòng thu thập đứng theo.

**Bỏ bớt**: tài liệu và cấu hình chỉ dành cho dự án gốc. Quy trình phát hành
viết lại gọn cho fork này — một workflow dựng bản universal và một trình cài
đặt tải nó về.

## Phát triển

```bash
make build                      # build hai binary Go
NORA_TEST_NO_AUTH=1 bats tests/ # bộ test shell
go test ./...                   # bộ test Go
cd app && ./build_app.sh release
```

Phát hành: cập nhật `VERSION` trong `nora`, tạo tag cùng số đó, rồi dựng và
đăng từ một máy có Go và Xcode:

```bash
./scripts/package_release.sh --version V0.1.0
gh release create V0.1.0 --title V0.1.0 dist/nora-macos.tar.gz dist/SHA256SUMS
```

`nora-macos.tar.gz` kèm `SHA256SUMS` chính là thứ `install.sh` tải về. Thử
trước khi đăng, cài y như người dùng sẽ cài, chỉ khác chỗ tải:

```bash
NORA_RELEASE_BASE="file://$PWD/dist" ./install.sh
```

Đẩy tag lên GitHub thì `.github/workflows/release.yml` chạy đúng các bước đó.
Workflow ghim runner `macos-26`: Swift 6.1 trên `macos-15` từ chối
`swiftLanguageMode` khi build universal, nó không hỏi toolchain xem có những
chế độ ngôn ngữ nào.

App có chế độ tự kiểm tra, chạy mọi bộ giải mã trên dữ liệu thật của máy:

```bash
app/.build/release/NoraUI --selftest
```

## Giấy phép

GPL-3.0 — kế thừa từ Mole. Xem [LICENSE](LICENSE).

Tên và biểu tượng "Mole" là thương hiệu của dự án Mole và không được dùng ở
đây. Xem [NOTICE](NOTICE) để biết chi tiết các thay đổi so với bản gốc.
