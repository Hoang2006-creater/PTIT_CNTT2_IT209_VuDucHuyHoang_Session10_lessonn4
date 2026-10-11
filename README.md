# Bài 4: Thiết lập Custom Network & Named Volume bằng Docker CLI

## 1. Giới thiệu & Mục tiêu
Mục tiêu của bài thực hành:
- **Tạo Custom Bridge Network (`app-net`)**: Cho phép các container trong cùng mạng giao tiếp nội bộ thông qua tên service (Automatic DNS Resolution) mà không phụ thuộc vào địa chỉ IP tĩnh.
- **Tạo Named Volume (`db-data`)**: Thiết lập cơ chế lưu trữ dữ liệu bền vững (Data Persistence) tách biệt khỏi vòng đời của container.
- **Kiểm thử Data Persistence**: Đảm bảo toàn vẹn dữ liệu khi container Database bị xóa cứng (`docker rm -f`) và khởi tạo lại container mới với cùng Named Volume.

---

## 2. Cấu trúc thư mục nộp bài
Theo yêu cầu nộp bài tại đường dẫn trên GitHub `homework/session_10/ex4/`:

```text
homework/session_10/ex4/
├── commands.sh      # Script tự động hóa toàn bộ quá trình thực thi & kiểm thử
└── README.md        # Hướng dẫn chi tiết, giải thích lý thuyết và kết quả kiểm tra
```

---

## 3. Kiến thức nền tảng

### 3.1. Custom Bridge Network vs Default Bridge Network
- **Default Bridge Network (`bridge`)**: Không hỗ trợ tự động phân giải tên miền (Automatic DNS resolution). Để các container gọi nhau bằng tên, cần cấu hình cồng kềnh với flag `--link` (đã bị coi là legacy).
- **Custom User-defined Bridge Network (`app-net`)**: 
  - Tự động cung cấp DNS Server nội bộ của Docker engine (127.0.0.11).
  - Các container có thể kết nối với nhau trực tiếp thông qua container name (`db-server`, `app-container`).
  - Đảm bảo tính cô lập và bảo mật cao hơn.

### 3.2. Named Volume trong Docker
- Dữ liệu của container thông thường nằm trong writable layer (storage driver) và sẽ bị xóa sạch khi container bị xóa (`docker rm`).
- **Named Volume** được Docker quản lý tại một vùng lưu trữ riêng biệt trên host (thường tại `/var/lib/docker/volumes/<volume_name>/_data` trên Linux).
- Dữ liệu trong Named Volume tồn tại độc lập với vòng đời của container. Khi container bị xóa, volume vẫn giữ nguyên và có thể mount lại cho container mới.

---

## 4. Các bước thực hiện chi tiết

### Bước 1: Tạo Custom Bridge Network
Tạo mạng bridge tùy biến tên `app-net`:
```bash
docker network create --driver bridge app-net
```
Kiểm tra mạng vừa tạo:
```bash
docker network ls | grep app-net
```

### Bước 2: Tạo Named Volume
Tạo Named Volume tên `db-data` để lưu trữ dữ liệu PostgreSQL:
```bash
docker volume create db-data
```
Kiểm tra volume vừa tạo:
```bash
docker volume ls | grep db-data
```

### Bước 3: Khởi chạy Database Container (`postgres:15-alpine`)
Khởi chạy container PostgreSQL tham gia mạng `app-net`, mount volume `db-data` vào thư mục lưu trữ dữ liệu của PostgreSQL `/var/lib/postgresql/data`:
```bash
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=testdb \
  postgres:15-alpine
```

### Bước 4: Khởi chạy Backend Container (`app-container`)
Khởi chạy Backend container cùng tham gia mạng `app-net`, truyền biến môi trường kết nối cơ sở dữ liệu qua hostname `db-server`:
```bash
docker run -d \
  --name app-container \
  --network app-net \
  -e DB_HOST=db-server \
  -e DB_PORT=5432 \
  -e DB_USER=postgres \
  -e DB_PASSWORD=secret \
  -e DB_NAME=testdb \
  alpine:latest sleep infinity
```

---

## 5. Kiểm tra & Kết quả mong đợi

### 5.1. Kiểm tra Network & DNS Resolution

1. **Kiểm tra thông tin chi tiết mạng `app-net`**:
```bash
docker network inspect app-net
```
*Kết quả mong đợi*: Cả hai container `db-server` và `app-container` đều xuất hiện trong danh sách `Containers` của mạng `app-net`.

2. **Kiểm tra DNS Resolution bằng lệnh `ping`**:
```bash
docker exec -it app-container ping -c 2 db-server
```
*Kết quả mong đợi*:
```text
PING db-server (172.18.0.2): 56 data bytes
64 bytes from 172.18.0.2: seq=0 ttl=64 time=0.081 ms
64 bytes from 172.18.0.2: seq=1 ttl=64 time=0.075 ms

--- db-server ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.075/0.078/0.081 ms
```
> **Nhận xét**: Container `app-container` giải mã thành công địa chỉ IP nội bộ của `db-server` thông qua DNS nội bộ của Docker.

---

### 5.2. Kiểm thử Data Persistence

1. **Tạo bảng và thêm dữ liệu vào `db-server`**:
```bash
docker exec -i db-server psql -U postgres -d testdb <<EOF
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100)
);

INSERT INTO users (name, email) VALUES 
    ('Nguyen Van A', 'vana@example.com'),
    ('Tran Thi B', 'thib@example.com');
EOF
```

2. **Truy vấn dữ liệu ban đầu**:
```bash
docker exec -i db-server psql -U postgres -d testdb -c "SELECT * FROM users;"
```
*Kết quả*:
```text
 id |     name      |       email        
----+---------------+--------------------
  1 | Nguyen Van A  | vana@example.com
  2 | Tran Thi B    | thib@example.com
(2 rows)
```

3. **Xóa cứng container Database**:
```bash
docker rm -f db-server
```

4. **Khởi chạy container Database mới gắn cùng volume `db-data`**:
```bash
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=testdb \
  postgres:15-alpine
```

5. **Xác minh dữ liệu không bị mất sau khi tái tạo container**:
```bash
docker exec -i db-server psql -U postgres -d testdb -c "SELECT * FROM users;"
```
*Kết quả mong đợi*:
```text
 id |     name      |       email        
----+---------------+--------------------
  1 | Nguyen Van A  | vana@example.com
  2 | Tran Thi B    | thib@example.com
(2 rows)
```
> **Kết luận**: Dữ liệu trong bảng `users` được bảo toàn nguyên vẹn sau khi container cũ bị xóa cứng và container mới được tạo lại nhờ Named Volume `db-data`.

---

## 6. Hướng dẫn chạy tự động bằng Script

Cấp quyền thực thi và chạy file `commands.sh`:
```bash
chmod +x commands.sh
./commands.sh
```

---

## 7. Dọn dẹp tài nguyên (Cleanup)
Sau khi hoàn thành bài test, dọn dẹp các tài nguyên đã tạo bằng các lệnh sau:
```bash
docker rm -f db-server app-container
docker network rm app-net
docker volume rm db-data
```
