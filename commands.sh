#!/bin/bash
# ==============================================================================
# Bài 4: Thiết lập Custom Network & Named Volume bằng Docker CLI
# Mục tiêu:
#   1. Tạo Custom Bridge Network (app-net) hỗ trợ DNS resolution giữa các container.
#   2. Tạo Named Volume (db-data) đảm bảo dữ liệu bền vững (Data Persistence).
#   3. Khởi chạy Database (PostgreSQL) và Backend (app-container).
#   4. Kiểm tra giao tiếp nội bộ qua hostname db-server.
#   5. Thực hiện kiểm thử tính toàn vẹn dữ liệu khi container DB bị xóa cứng và tạo lại.
# ==============================================================================

set -e

echo "=== [BƯỚC 0] DỌN DẸP MÔI TRƯỜNG CŨ (NẾU CÓ) ==="
docker rm -f db-server app-container 2>/dev/null || true
docker network rm app-net 2>/dev/null || true
docker volume rm db-data 2>/dev/null || true
echo "-> Môi trường đã sẵn sàng."
echo ""

echo "=== [BƯỚC 1] TẠO CUSTOM BRIDGE NETWORK ==="
docker network create --driver bridge app-net
echo "-> Đã tạo network app-net."
docker network ls | grep app-net
echo ""

echo "=== [BƯỚC 2] TẠO NAMED VOLUME ==="
docker volume create db-data
echo "-> Đã tạo volume db-data."
docker volume ls | grep db-data
echo ""

echo "=== [BƯỚC 3] KHỞI CHẠY POSTGRESQL DATABASE CONTAINER ==="
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=testdb \
  postgres:15-alpine

echo "-> Database container (db-server) đang khởi chạy..."
echo "-> Chờ PostgreSQL sẵn sàng tiếp nhận kết nối..."
until docker exec db-server pg_isready -U postgres -d testdb >/dev/null 2>&1; do
  sleep 1
done
echo "-> PostgreSQL đã sẵn sàng!"
echo ""

echo "=== [BƯỚC 4] KHỞI CHẠY BACKEND CONTAINER ==="
# Khởi chạy container backend app-container trong mạng app-net, truyền cấu hình DB
docker run -d \
  --name app-container \
  --network app-net \
  -e DB_HOST=db-server \
  -e DB_PORT=5432 \
  -e DB_USER=postgres \
  -e DB_PASSWORD=secret \
  -e DB_NAME=testdb \
  alpine:latest sleep infinity

echo "-> Backend container (app-container) đã khởi chạy."
echo ""

echo "=== [BƯỚC 5] KIỂM TRA NETWORK & DNS RESOLUTION ==="
echo "Kiểm tra thông tin chi tiết mạng app-net:"
docker network inspect app-net

echo ""
echo "Kiểm tra ping từ app-container tới db-server bằng hostname:"
docker exec app-container ping -c 2 db-server
echo "-> Phân giải DNS và kết nối nội bộ thành công!"
echo ""

echo "=== [BƯỚC 6] KIỂM THỬ DATA PERSISTENCE ==="
echo "1. Thêm dữ liệu mẫu vào cơ sở dữ liệu trên db-server..."
docker exec -i db-server psql -U postgres -d testdb <<EOF
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (name, email) VALUES
    ('Nguyen Van A', 'vana@example.com'),
    ('Tran Thi B', 'thib@example.com'),
    ('Le Van C', 'vanc@example.com');
EOF

echo ""
echo "Dữ liệu hiện tại trong bảng users:"
docker exec -i db-server psql -U postgres -d testdb -c "SELECT * FROM users;"

echo ""
echo "2. Xóa cứng container db-server (docker rm -f db-server)..."
docker rm -f db-server
echo "-> Đã xóa cứng container db-server."

echo ""
echo "3. Khởi chạy lại container db-server mới gắn cùng volume db-data..."
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=testdb \
  postgres:15-alpine

echo "-> Chờ PostgreSQL mới khởi động xong..."
until docker exec db-server pg_isready -U postgres -d testdb >/dev/null 2>&1; do
  sleep 1
done
echo "-> PostgreSQL mới đã sẵn sàng!"

echo ""
echo "4. Xác minh dữ liệu trong container mới tái tạo:"
docker exec -i db-server psql -U postgres -d testdb -c "SELECT * FROM users;"

echo ""
echo "=============================================================================="
echo "-> THÀNH CÔNG: Dữ liệu vẫn được bảo toàn nguyên vẹn nhờ Docker Named Volume!"
echo "=============================================================================="
