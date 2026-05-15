# Library Management System

REST API for a library management system developed for the Data Management Systems course (SGD) 2025/2026.

**Stack:** Python 3 · Flask · PostgreSQL · psycopg2

---

## Prerequisites

- Python 3.10+
- PostgreSQL 14+
- pip

---

## Installation

### 1. Clone the repository

```bash
git clone <repository-url>
cd library-management
```

### 2. Create and activate a virtual environment

```bash
python -m venv venv

# Windows (PowerShell)
.\venv\Scripts\Activate.ps1

# Linux / macOS
source venv/bin/activate
```

### 3. Install dependencies

```bash
pip install -r requirements.txt
```

### 4. Configure environment variables

Create a `.env` file in the project root with the following content:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=library
DB_USER=<your_postgres_user>
DB_PASSWORD=<your_postgres_password>
```

### 5. Set up the database

Connect to PostgreSQL and create the database:

```sql
CREATE DATABASE library;
```

Then run the scripts in order:

```bash
psql -U <your_postgres_user> -d library -f db/create_tables.sql
psql -U <your_postgres_user> -d library -f db/populate_data.sql
```

---

## Running the server

```bash
cd api
python app.py
```

The server starts at `http://localhost:8080`.

---

## API Overview

All endpoints are prefixed with `/sgdproj`. Authentication is done via `username` and `password` fields in the JSON request body.

| # | Method | Endpoint | Role |
|---|--------|----------|------|
| 1 | POST | `/sgdproj/user` | Public |
| 2 | POST | `/sgdproj/book` | Admin |
| 3 | PUT | `/sgdproj/update_copies` | Admin |
| 4 | GET | `/sgdproj/list_books_by_genre` | Admin, Librarian |
| 5 | GET | `/sgdproj/find_book_by_name` | Admin, Librarian |
| 6 | GET | `/sgdproj/find_book_by_isbn` | Admin, Librarian |
| 7 | GET | `/sgdproj/loaned_books` | Admin, Librarian |
| 8 | GET | `/sgdproj/loaned_book` | Admin, Librarian |
| 9 | GET | `/sgdproj/TopLoanedBooks/{N}` | Admin, Librarian |
| 10 | GET | `/sgdproj/TopLoaners/{N}` | Admin, Librarian |
| 11 | GET | `/sgdproj/available_books_by_genre` | All authenticated |
| 12 | GET | `/sgdproj/check_book` | All authenticated |
| 13 | POST | `/sgdproj/borrow_book` | All authenticated |
| 14 | POST | `/sgdproj/report/submit_review` | All authenticated |
| 15 | POST | `/sgdproj/return_book` | All authenticated |
| 16 | GET | `/sgdproj/report/TopLoanedGenres12Months/{N}` | Admin, Librarian |

All responses follow the structure:

```json
{
  "status": 200,
  "errors": null,
  "results": ...
}
```

Status codes: `200` success · `400` bad request · `500` internal server error

---

## Testing

Import the Postman collection from the `tests/` folder and run the requests against `http://localhost:8080`.
