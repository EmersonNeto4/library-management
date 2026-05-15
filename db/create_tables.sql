-- =============================================
-- Library Management System
-- Data Management Systems Project 2025/2026
-- ELEMENTO A — setup completo
-- =============================================
-- INSTRUÇÕES:
--   1. Corre este ficheiro como superuser do PostgreSQL
--   2. Ele apaga (se existir) e recria a base de dados
--   3. Depois cria todas as tabelas e constraints
-- =============================================


-- ── 1. CRIAR BASE DE DADOS ──────────────────
-- (corre isto separado se usares psql, pois não podes
--  estar dentro da BD que vais apagar)

DROP DATABASE IF EXISTS library_db;
CREATE DATABASE library_db
    WITH ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE   = 'en_US.UTF-8'
    TEMPLATE   = template0;

\c library_db   -- liga à nova BD (só funciona no psql)


-- ── 2. TABELAS ───────────────────────────────

CREATE TABLE users (
    user_id    SERIAL,
    username   VARCHAR(50)  NOT NULL,
    email      VARCHAR(100) NOT NULL,
    password   VARCHAR(255) NOT NULL,
    created_at TIMESTAMP    NOT NULL DEFAULT NOW(),
    PRIMARY KEY(user_id)
);

CREATE TABLE books (
    isbn            VARCHAR(20),
    title           VARCHAR(200) NOT NULL,
    description     TEXT,
    pages           INTEGER      NOT NULL,
    copies          INTEGER      NOT NULL,
    registered_date DATE         NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY(isbn)
);

CREATE TABLE genres (
    genre_id   SERIAL,
    genre_name VARCHAR(50) NOT NULL,
    PRIMARY KEY(genre_id)
);

CREATE TABLE loans (
    loan_id       SERIAL,
    loan_date     DATE        NOT NULL DEFAULT CURRENT_DATE,
    return_date   DATE,                          -- NULL = livro ainda emprestado
    books_isbn    VARCHAR(20) NOT NULL,
    users_user_id INTEGER     NOT NULL,
    PRIMARY KEY(loan_id)
);

CREATE TABLE reviews (
    rating        INTEGER     NOT NULL,
    comment       TEXT,
    review_date   TIMESTAMP   NOT NULL DEFAULT NOW(),
    books_isbn    VARCHAR(20) NOT NULL,
    users_user_id INTEGER     NOT NULL,
    PRIMARY KEY(books_isbn, users_user_id)       -- 1 review por user por livro
);

CREATE TABLE admin (
    admin_level   INTEGER NOT NULL,
    users_user_id INTEGER NOT NULL,
    PRIMARY KEY(users_user_id)
);

CREATE TABLE librarian (
    n_mec         INTEGER NOT NULL,
    users_user_id INTEGER NOT NULL,
    PRIMARY KEY(users_user_id)
);

CREATE TABLE reader (
    n_estudante   BIGINT  NOT NULL,
    users_user_id INTEGER NOT NULL,
    PRIMARY KEY(users_user_id)
);

CREATE TABLE author (
    author_id SERIAL,
    name      VARCHAR(512) NOT NULL,
    PRIMARY KEY(author_id)
);

CREATE TABLE author_books (
    author_author_id INTEGER     NOT NULL,
    books_isbn       VARCHAR(20) NOT NULL,
    PRIMARY KEY(author_author_id, books_isbn)
);

CREATE TABLE books_genres (
    books_isbn      VARCHAR(20) NOT NULL,
    genres_genre_id INTEGER     NOT NULL,
    PRIMARY KEY(books_isbn, genres_genre_id)
);


-- ── 3. CONSTRAINTS — users ───────────────────

ALTER TABLE users
    ADD CONSTRAINT unique_username UNIQUE (username);

ALTER TABLE users
    ADD CONSTRAINT unique_email UNIQUE (email);


-- ── 4. CONSTRAINTS — books ───────────────────

ALTER TABLE books
    ADD CONSTRAINT chk_books_pages  CHECK (pages > 0);

ALTER TABLE books
    ADD CONSTRAINT chk_books_copies CHECK (copies >= 0);


-- ── 5. CONSTRAINTS — genres ──────────────────

ALTER TABLE genres
    ADD CONSTRAINT unique_genre_name UNIQUE (genre_name);


-- ── 6. FK + CONSTRAINTS — loans ──────────────

ALTER TABLE loans
    ADD CONSTRAINT loans_fk1
        FOREIGN KEY (books_isbn)    REFERENCES books(isbn);

ALTER TABLE loans
    ADD CONSTRAINT loans_fk2
        FOREIGN KEY (users_user_id) REFERENCES users(user_id);

-- Garante que o mesmo user não tem o mesmo livro emprestado 2x em simultâneo
-- (usa partial unique index porque CHECK(UNIQUE) não é válido em PostgreSQL)
CREATE UNIQUE INDEX unique_active_loan
    ON loans (users_user_id, books_isbn)
    WHERE return_date IS NULL;


-- ── 7. FK + CONSTRAINTS — reviews ────────────

ALTER TABLE reviews
    ADD CONSTRAINT reviews_fk1
        FOREIGN KEY (books_isbn)    REFERENCES books(isbn);

ALTER TABLE reviews
    ADD CONSTRAINT reviews_fk2
        FOREIGN KEY (users_user_id) REFERENCES users(user_id);

ALTER TABLE reviews
    ADD CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5);

-- UNIQUE (users_user_id, books_isbn) já garantido pela PRIMARY KEY — não é necessário


-- ── 8. FK + CONSTRAINTS — herança (admin, librarian, reader) ─

ALTER TABLE admin
    ADD CONSTRAINT admin_fk1
        FOREIGN KEY (users_user_id) REFERENCES users(user_id);

ALTER TABLE librarian
    ADD CONSTRAINT librarian_fk1
        FOREIGN KEY (users_user_id) REFERENCES users(user_id);

ALTER TABLE librarian
    ADD CONSTRAINT unique_n_mec UNIQUE (n_mec);

ALTER TABLE reader
    ADD CONSTRAINT reader_fk1
        FOREIGN KEY (users_user_id) REFERENCES users(user_id);

ALTER TABLE reader
    ADD CONSTRAINT unique_n_estudante UNIQUE (n_estudante);


-- ── 9. FK — author_books, books_genres ────────

ALTER TABLE author_books
    ADD CONSTRAINT author_books_fk1
        FOREIGN KEY (author_author_id) REFERENCES author(author_id);

ALTER TABLE author_books
    ADD CONSTRAINT author_books_fk2
        FOREIGN KEY (books_isbn)       REFERENCES books(isbn);

ALTER TABLE books_genres
    ADD CONSTRAINT books_genres_fk1
        FOREIGN KEY (books_isbn)       REFERENCES books(isbn);

ALTER TABLE books_genres
    ADD CONSTRAINT books_genres_fk2
        FOREIGN KEY (genres_genre_id)  REFERENCES genres(genre_id);


-- ── 10. VERIFICAÇÃO FINAL ─────────────────────
-- Corre após o script para confirmar que tudo foi criado:

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
