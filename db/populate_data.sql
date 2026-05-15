-- =============================================
-- Library Management System
-- Data Management Systems Project 2025/2026
-- POPULATE DATA — Completo
-- Géneros + Autores + Livros + Utilizadores
-- + Empréstimos + Reviews
-- =============================================
-- ESTRUTURA:
--   10 géneros
--   50 autores
--   1000 livros (100 por género)
--      → 80 livros exclusivos por género (80%)
--      → 20 livros partilhados com género seguinte (20%)
--   author_books: 1 autor principal + ~33% com 2º autor
--   1 admin + 1 librarian + 100 readers
--   600 loans (5 históricos + 1 ativo por reader)
--   200 reviews (2 por reader)
-- =============================================


-- ── 0. LIMPAR DADOS ANTERIORES ───────────────
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

-- 4a. Atribuição base
INSERT INTO books_genres (books_isbn, genres_genre_id)
SELECT
    '978' || LPAD(i::text, 10, '0'),
    ceil(i::float / 100)::int
FROM generate_series(1, 1000) AS s(i);

-- 4b. Atribuição secundária
INSERT INTO books_genres (books_isbn, genres_genre_id)
SELECT
    '978' || LPAD(i::text, 10, '0'),
    (ceil(i::float / 100)::int % 10) + 1
FROM generate_series(1, 1000) AS s(i)
WHERE ((i - 1) % 100) >= 80;


-- ── 5. AUTHOR_BOOKS ──────────────────────────

-- 5a. Autor principal
INSERT INTO author_books (author_author_id, books_isbn)
SELECT
    ((i - 1) % 50) + 1,
    '978' || LPAD(i::text, 10, '0')
FROM generate_series(1, 1000) AS s(i);

-- 5b. Segundo autor (~33% dos livros)
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
-- user_id: 3 a 102 (admin=1, librarian=2)
-- username:    reader_001 a reader_100
-- n_estudante: 2020000001 a 2020000100

INSERT INTO users (username, email, password, created_at)
SELECT
    'reader_' || LPAD(i::text, 3, '0'),
    'reader'  || LPAD(i::text, 3, '0') || '@library.com',
    'password123',
    NOW() - (i * INTERVAL '7 days')
FROM generate_series(1, 100) AS s(i);

INSERT INTO reader (users_user_id, n_estudante)
SELECT
    user_id,
    2020000000 + ROW_NUMBER() OVER (ORDER BY user_id)
FROM users
WHERE username LIKE 'reader_%'
ORDER BY user_id;


-- ── 7b. HASH DAS PASSWORDS ───────────────────
-- As passwords foram inseridas em texto simples para facilitar a leitura.
-- Esta instrução aplica o hash MD5 a todos os utilizadores de uma vez,
-- ficando consistente com o que o endpoint 1 faz em Python (hashlib.md5).

UPDATE users SET password = md5(password);


-- ── 8. LOANS ─────────────────────────────────
-- Cada reader (user_id = r+2, r de 1 a 100) tem:
--   5 empréstimos históricos (devolvidos) → livros 1-500
--   1 empréstimo ativo (não devolvido)    → livros 501-600
-- Total: 500 históricos + 100 ativos = 600 loans
--
-- Distribuição de livros:
--   Reader r, loan j (0..4) → livro ((r-1)*5 + j) + 1
--   Ex: reader 1 → livros 1, 2, 3, 4, 5
--   Ex: reader 2 → livros 6, 7, 8, 9, 10
--   Cada livro 1-500 é emprestado exatamente 1 vez (histórico)
--
--   Ativo: reader r → livro 500 + r
--   Ex: reader 1 → livro 501
--   Ex: reader 100 → livro 600
--   Cada livro 501-600 tem 1 empréstimo ativo (cópias >= 1, OK)
--
-- Datas:
--   loan_date:   2023-01-01 + (r*3 + j*30) dias
--   return_date: loan_date + 14 dias
--   Empréstimo ativo: loan_date 2024-06-01 + r dias

-- 8a. Empréstimos históricos (devolvidos)
INSERT INTO loans (loan_date, return_date, books_isbn, users_user_id)
SELECT
    DATE '2023-01-01' + (r * 3 + j * 30) * INTERVAL '1 day'            AS loan_date,
    DATE '2023-01-01' + (r * 3 + j * 30 + 14) * INTERVAL '1 day'       AS return_date,
    '978' || LPAD(((r - 1) * 5 + j + 1)::text, 10, '0')                AS books_isbn,
    r + 2                                                                AS users_user_id
FROM generate_series(1, 100) AS s(r),
     generate_series(0, 4)   AS t(j);

-- 8b. Empréstimos ativos (não devolvidos)
INSERT INTO loans (loan_date, return_date, books_isbn, users_user_id)
SELECT
    DATE '2024-06-01' + r * INTERVAL '1 day'    AS loan_date,
    NULL                                         AS return_date,
    '978' || LPAD((500 + r)::text, 10, '0')     AS books_isbn,
    r + 2                                        AS users_user_id
FROM generate_series(1, 100) AS s(r);


-- ── 9. REVIEWS ───────────────────────────────
-- Cada reader faz review dos seus 2 primeiros livros emprestados
-- (livros que já foram devolvidos — empréstimos históricos j=0 e j=1)
-- Garante: só se faz review de livros emprestados (regra do enunciado)
--
-- Reader r → reviews dos livros (r-1)*5+1 e (r-1)*5+2
-- review_date: 7 dias após o return_date do empréstimo correspondente
--
-- Ratings variados mas realistas:
--   Review 1 (k=1): rating = (r % 5) + 1       → distribui 1 a 5
--   Review 2 (k=2): rating = ((r + 2) % 5) + 1 → desfasado 2

INSERT INTO reviews (rating, comment, review_date, books_isbn, users_user_id)
SELECT
    CASE k
        WHEN 1 THEN (r % 5) + 1
        WHEN 2 THEN ((r + 2) % 5) + 1
    END                                                                         AS rating,

    CASE k
        WHEN 1 THEN 'Really enjoyed this book. Would recommend to others. Volume ' || ((r-1)*5 + k) || '.'
        WHEN 2 THEN 'An interesting read with great depth. Volume ' || ((r-1)*5 + k) || '.'
    END                                                                         AS comment,

    -- review_date = loan_date + 14 dias (return) + 7 dias = loan_date + 21 dias
    DATE '2023-01-01' + (r * 3 + (k-1) * 30 + 21) * INTERVAL '1 day'         AS review_date,

    '978' || LPAD(((r - 1) * 5 + k)::text, 10, '0')                           AS books_isbn,

    r + 2                                                                       AS users_user_id

FROM generate_series(1, 100) AS s(r),
     generate_series(1, 2)   AS t(k);


-- ── 10. VERIFICAÇÃO ──────────────────────────

-- Verificação 1: livros por género (deve ser 100 em todos)
SELECT
    g.genre_id,
    g.genre_name,
    COUNT(bg.books_isbn) AS total_books
FROM genres g
JOIN books_genres bg ON g.genre_id = bg.genres_genre_id
GROUP BY g.genre_id, g.genre_name
ORDER BY g.genre_id;

-- Verificação 2: exclusivos vs partilhados (exclusive_pct deve ser 80.0)
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

-- Verificação 5: loans (históricos=500, ativos=100, total=600)
SELECT
    CASE WHEN return_date IS NULL THEN 'ativo' ELSE 'histórico' END AS tipo,
    COUNT(*) AS total
FROM loans
GROUP BY (return_date IS NULL)
ORDER BY tipo;

-- Verificação 6: reviews por reader (deve ser 2 em todos)
SELECT
    MIN(total_reviews) AS min_reviews_por_reader,
    MAX(total_reviews) AS max_reviews_por_reader,
    COUNT(*)           AS total_readers_com_reviews
FROM (
    SELECT users_user_id, COUNT(*) AS total_reviews
    FROM reviews
    GROUP BY users_user_id
) sub;