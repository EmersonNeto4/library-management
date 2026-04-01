-- =============================================
-- Library Management System
-- Data Management Systems Project 2025/2026
-- POPULATE DATA — Semana 2
-- Géneros + Autores + Livros + Utilizadores
-- =============================================
-- ESTRUTURA:
--   10 géneros
--   50 autores
--   1000 livros (100 por género)
--      → 80 livros exclusivos por género (80%)
--      → 20 livros partilhados com o género seguinte (20%)
--   author_books: 1 autor principal + ~33% com 2º autor
--   1 admin + 1 librarian + 100 readers
-- =============================================


-- ── 0. LIMPAR DADOS ANTERIORES ───────────────
-- Garante execução limpa mesmo que já existam dados
TRUNCATE TABLE books_genres, author_books, reviews, loans,
              reader, librarian, admin, author, books, genres, users
RESTART IDENTITY CASCADE;


-- ── 1. GÉNEROS (10) ──────────────────────────

INSERT INTO genres (genre_name) VALUES
    ('Fiction'),
    ('Mystery'),
    ('Science Fiction'),
    ('Fantasy'),
    ('Biography'),
    ('History'),
    ('Self-Help'),
    ('Romance'),
    ('Thriller'),
    ('Horror');


-- ── 2. AUTORES (50) ──────────────────────────

INSERT INTO author (name) VALUES
    ('George Orwell'),
    ('Agatha Christie'),
    ('Isaac Asimov'),
    ('J.R.R. Tolkien'),
    ('Walter Isaacson'),
    ('Yuval Noah Harari'),
    ('James Clear'),
    ('Nicholas Sparks'),
    ('John Grisham'),
    ('Stephen King'),
    ('Ernest Hemingway'),
    ('Arthur Conan Doyle'),
    ('Philip K. Dick'),
    ('Brandon Sanderson'),
    ('Ron Chernow'),
    ('Doris Kearns Goodwin'),
    ('Malcolm Gladwell'),
    ('Nora Roberts'),
    ('Lee Child'),
    ('Dean Koontz'),
    ('F. Scott Fitzgerald'),
    ('Raymond Chandler'),
    ('Ursula K. Le Guin'),
    ('Neil Gaiman'),
    ('Robert Caro'),
    ('Barbara Tuchman'),
    ('Dale Carnegie'),
    ('Danielle Steel'),
    ('Tom Clancy'),
    ('Peter Straub'),
    ('Virginia Woolf'),
    ('Dashiell Hammett'),
    ('Frank Herbert'),
    ('Robin Hobb'),
    ('David McCullough'),
    ('Anthony Beevor'),
    ('Robert Greene'),
    ('Jojo Moyes'),
    ('Vince Flynn'),
    ('Shirley Jackson'),
    ('Gabriel Garcia Marquez'),
    ('Tana French'),
    ('Kim Stanley Robinson'),
    ('Patrick Rothfuss'),
    ('Erik Larson'),
    ('Ken Follett'),
    ('Susan Jeffers'),
    ('Lisa Kleypas'),
    ('Brad Thor'),
    ('Joe Hill');


-- ── 3. LIVROS (1000) ─────────────────────────
-- ISBN: '978' + número de 10 dígitos com zeros à esquerda
-- Género g cobre livros (g-1)*100+1 até g*100
-- Páginas variam realisticamente por género
-- Cópias entre 1 e 10

INSERT INTO books (isbn, title, description, pages, copies, registered_date)
SELECT
    '978' || LPAD(i::text, 10, '0') AS isbn,

    CASE ceil(i::float / 100)::int
        WHEN 1  THEN 'Fiction Chronicle '   || ((i - 1)   % 100 + 1)
        WHEN 2  THEN 'Mystery Case '        || ((i - 101) % 100 + 1)
        WHEN 3  THEN 'Sci-Fi Odyssey '      || ((i - 201) % 100 + 1)
        WHEN 4  THEN 'Fantasy Realm '       || ((i - 301) % 100 + 1)
        WHEN 5  THEN 'Life of '             || ((i - 401) % 100 + 1)
        WHEN 6  THEN 'Historical Account '  || ((i - 501) % 100 + 1)
        WHEN 7  THEN 'Self-Help Guide '     || ((i - 601) % 100 + 1)
        WHEN 8  THEN 'Romance Story '       || ((i - 701) % 100 + 1)
        WHEN 9  THEN 'Thriller Plot '       || ((i - 801) % 100 + 1)
        WHEN 10 THEN 'Horror Tale '         || ((i - 901) % 100 + 1)
    END AS title,

    'A compelling ' ||
    CASE ceil(i::float / 100)::int
        WHEN 1  THEN 'fiction'
        WHEN 2  THEN 'mystery'
        WHEN 3  THEN 'science fiction'
        WHEN 4  THEN 'fantasy'
        WHEN 5  THEN 'biography'
        WHEN 6  THEN 'history'
        WHEN 7  THEN 'self-help'
        WHEN 8  THEN 'romance'
        WHEN 9  THEN 'thriller'
        WHEN 10 THEN 'horror'
    END
    || ' book that takes the reader on an unforgettable journey. Volume '
    || i || ' of the library collection.' AS description,

    CASE ceil(i::float / 100)::int
        WHEN 1  THEN 200 + (i * 7  % 300)
        WHEN 2  THEN 180 + (i * 11 % 250)
        WHEN 3  THEN 250 + (i * 13 % 350)
        WHEN 4  THEN 300 + (i * 17 % 500)
        WHEN 5  THEN 250 + (i * 9  % 350)
        WHEN 6  THEN 300 + (i * 11 % 400)
        WHEN 7  THEN 150 + (i * 7  % 200)
        WHEN 8  THEN 200 + (i * 13 % 250)
        WHEN 9  THEN 220 + (i * 11 % 280)
        WHEN 10 THEN 200 + (i * 9  % 300)
    END AS pages,

    (1 + (i % 10)) AS copies,

    (DATE '2018-01-01' + ((i * 2) % 2191) * INTERVAL '1 day')::date AS registered_date

FROM generate_series(1, 1000) AS s(i);


-- ── 4. BOOKS_GENRES ──────────────────────────
-- Livros 1-80 de cada grupo   → exclusivos do género principal (80%)
-- Livros 81-100 de cada grupo → também no género seguinte cíclico (20%)

-- 4a. Atribuição base — todos os 1000 livros ao seu género principal
INSERT INTO books_genres (books_isbn, genres_genre_id)
SELECT
    '978' || LPAD(i::text, 10, '0'),
    ceil(i::float / 100)::int
FROM generate_series(1, 1000) AS s(i);

-- 4b. Atribuição secundária — livros 81-100 de cada grupo ao género seguinte
INSERT INTO books_genres (books_isbn, genres_genre_id)
SELECT
    '978' || LPAD(i::text, 10, '0'),
    (ceil(i::float / 100)::int % 10) + 1
FROM generate_series(1, 1000) AS s(i)
WHERE ((i - 1) % 100) >= 80;


-- ── 5. AUTHOR_BOOKS ──────────────────────────
-- Autor principal: distribuído ciclicamente pelos 50 autores
-- ~33% dos livros têm um 2º autor diferente do 1º

-- 5a. Autor principal
INSERT INTO author_books (author_author_id, books_isbn)
SELECT
    ((i - 1) % 50) + 1,
    '978' || LPAD(i::text, 10, '0')
FROM generate_series(1, 1000) AS s(i);

-- 5b. Segundo autor (múltiplos de 3, garantindo que é diferente do principal)
INSERT INTO author_books (author_author_id, books_isbn)
SELECT
    (i % 50) + 1,
    '978' || LPAD(i::text, 10, '0')
FROM generate_series(1, 1000) AS s(i)
WHERE i % 3 = 0
  AND (i % 50) + 1 <> ((i - 1) % 50) + 1;


-- ── 6. UTILIZADORES — Admin e Librarian ──────

INSERT INTO users (username, email, password, created_at) VALUES
    ('admin1',     'admin@library.com',     'password123', NOW()),
    ('librarian1', 'librarian@library.com', 'password123', NOW());

INSERT INTO admin (users_user_id, admin_level)
VALUES (
    (SELECT user_id FROM users WHERE username = 'admin1'), 1
);

INSERT INTO librarian (users_user_id, n_mec)
VALUES (
    (SELECT user_id FROM users WHERE username = 'librarian1'), 12345
);


-- ── 7. UTILIZADORES — 100 Readers ────────────
-- username:    reader_001 a reader_100
-- email:       reader001@library.com a reader100@library.com
-- n_estudante: 2020000001 a 2020000100
-- created_at:  datas variadas nos últimos 2 anos

INSERT INTO users (username, email, password, created_at)
SELECT
    'reader_' || LPAD(i::text, 3, '0'),
    'reader'  || LPAD(i::text, 3, '0') || '@library.com',
    'password123',
    NOW() - (i * INTERVAL '7 days')   -- espaçados 7 dias entre si
FROM generate_series(1, 100) AS s(i);

INSERT INTO reader (users_user_id, n_estudante)
SELECT
    user_id,
    2020000000 + ROW_NUMBER() OVER (ORDER BY user_id)
FROM users
WHERE username LIKE 'reader_%'
ORDER BY user_id;


-- ── 8. VERIFICAÇÃO ───────────────────────────

-- Verificação 1: livros por género (deve ser 100 em todos)
SELECT
    g.genre_id,
    g.genre_name,
    COUNT(bg.books_isbn) AS total_books
FROM genres g
JOIN books_genres bg ON g.genre_id = bg.genres_genre_id
GROUP BY g.genre_id, g.genre_name
ORDER BY g.genre_id;

-- Verificação 2: exclusivos vs partilhados por género (exclusive_pct deve ser 80.0)
SELECT
    g.genre_id,
    g.genre_name,
    COUNT(CASE WHEN sub.genre_count = 1 THEN 1 END) AS exclusive_books,
    COUNT(CASE WHEN sub.genre_count > 1 THEN 1 END) AS shared_books,
    ROUND(
        COUNT(CASE WHEN sub.genre_count = 1 THEN 1 END)::numeric
        / COUNT(*) * 100, 1
    ) AS exclusive_pct
FROM genres g
JOIN books_genres bg ON g.genre_id = bg.genres_genre_id
JOIN (
    SELECT books_isbn, COUNT(*) AS genre_count
    FROM books_genres
    GROUP BY books_isbn
) sub ON bg.books_isbn = sub.books_isbn
GROUP BY g.genre_id, g.genre_name
ORDER BY g.genre_id;

-- Verificação 3: autores por livro
SELECT
    CASE
        WHEN author_count = 1 THEN '1 autor'
        WHEN author_count = 2 THEN '2 autores'
        ELSE '3+ autores'
    END AS autores,
    COUNT(*) AS livros
FROM (
    SELECT books_isbn, COUNT(*) AS author_count
    FROM author_books
    GROUP BY books_isbn
) sub
GROUP BY author_count
ORDER BY author_count;

-- Verificação 4: utilizadores por tipo (admin=1, librarian=1, reader=100)
SELECT 'admin'     AS tipo, COUNT(*) AS total FROM admin
UNION ALL
SELECT 'librarian' AS tipo, COUNT(*) AS total FROM librarian
UNION ALL
SELECT 'reader'    AS tipo, COUNT(*) AS total FROM reader;