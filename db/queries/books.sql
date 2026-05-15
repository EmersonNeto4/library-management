-- =============================================
-- Library Management System
-- Data Management Systems Project 2025/2026
-- QUERIES — books.sql
-- Endpoints cobertos:
--   1. Register User         (POST /sgdproj/user)
--   2. Add Book              (POST /sgdproj/book)
--   3. Modify Copies         (PUT  /sgdproj/updade_copies)
--   4. List Books by Genre   (GET  /sgdproj/list_books_by_genre)
--   5. Find Book by Name     (GET  /sgdproj/find_book_by_name)
--   6. Find Book by ISBN     (GET  /sgdproj/find_book_by_isbn)
-- =============================================
-- NOTAS PARA O ELEMENTO B (API):
--   - Todos os parâmetros indicados com %(param)s
--     são passados via psycopg2 (nunca concatenar strings!)
--   - Cada endpoint de escrita é uma transação — usar BEGIN/COMMIT
--   - Em caso de erro fazer ROLLBACK
--   - Autenticação deve ser verificada antes de
--     executar a query principal (ver AUTH abaixo)
-- =============================================


-- =============================================
-- AUTENTICAÇÃO (usar em TODOS os endpoints)
-- =============================================
-- Parâmetros: %(username)s, %(password)s

-- AUTH.1 — Verificar credenciais e obter user_id + tipo
SELECT
    u.user_id,
    u.username,
    CASE
        WHEN a.users_user_id IS NOT NULL THEN 'admin'
        WHEN l.users_user_id IS NOT NULL THEN 'librarian'
        WHEN r.users_user_id IS NOT NULL THEN 'reader'
    END AS user_type
FROM users u
LEFT JOIN admin     a ON a.users_user_id = u.user_id
LEFT JOIN librarian l ON l.users_user_id = u.user_id
LEFT JOIN reader    r ON r.users_user_id = u.user_id
WHERE u.username = %(username)s
  AND u.password = %(password)s;

-- Se não retornar resultados → 400 (credenciais inválidas)
-- Guardar user_type para verificar permissões em cada endpoint


-- =============================================
-- ENDPOINT 1 — Register User
-- POST /sgdproj/user
-- =============================================
-- Parâmetros: %(username)s, %(email)s, %(password)s,
--             %(user_type)s ('reader' ou 'librarian')
--             %(n_estudante)s (só se reader)
--             %(n_mec)s       (só se librarian)

-- REG.1 — Inserir na tabela users
INSERT INTO users (username, email, password, created_at)
VALUES (%(username)s, %(email)s, %(password)s, NOW())
RETURNING user_id;

-- REG.2a — Se user_type = 'reader'
INSERT INTO reader (users_user_id, n_estudante)
VALUES (%(user_id)s, %(n_estudante)s);

-- REG.2b — Se user_type = 'librarian'
INSERT INTO librarian (users_user_id, n_mec)
VALUES (%(user_id)s, %(n_mec)s);

-- Erros a tratar:
--   username já existe → 400
--   email já existe    → 400
--   erro inesperado    → 500


-- =============================================
-- ENDPOINT 2 — Add Book
-- POST /sgdproj/book
-- Apenas ADMIN
-- =============================================
-- Parâmetros: %(isbn)s, %(title)s, %(description)s,
--             %(pages)s, %(copies)s, %(author_name)s
--             %(genre_id)s (iterar para cada género)

-- BOOK.1 — Verificar se o ISBN já existe
SELECT isbn
FROM books
WHERE isbn = %(isbn)s;

-- BOOK.2 — Verificar se o autor já existe
SELECT author_id
FROM author
WHERE name = %(author_name)s;

-- BOOK.3 — Inserir autor novo (só se não existir)
INSERT INTO author (name)
VALUES (%(author_name)s)
RETURNING author_id;

-- BOOK.4 — Inserir o livro
INSERT INTO books (isbn, title, description, pages, copies, registered_date)
VALUES (%(isbn)s, %(title)s, %(description)s, %(pages)s, %(copies)s, CURRENT_DATE)
RETURNING isbn;

-- BOOK.5 — Associar autor ao livro
INSERT INTO author_books (author_author_id, books_isbn)
VALUES (%(author_id)s, %(isbn)s);

-- BOOK.6 — Verificar se o género existe (executar para cada genre_id)
SELECT genre_id
FROM genres
WHERE genre_id = %(genre_id)s;

-- BOOK.7 — Associar género ao livro (executar para cada genre_id validado)
INSERT INTO books_genres (books_isbn, genres_genre_id)
VALUES (%(isbn)s, %(genre_id)s);

-- Erros a tratar:
--   user não é admin    → 400
--   ISBN já existe      → 400
--   copies < 1          → 400
--   pages <= 0          → 400
--   género não existe   → 400
--   lista géneros vazia → 400
--   erro inesperado     → 500

-- Transação completa (pseudocódigo para o Elemento B):
-- BEGIN
--   verificar admin
--   BOOK.1 → se existe, ROLLBACK + 400
--   BOOK.2 → se não existe autor, BOOK.3
--   BOOK.4 → inserir livro
--   BOOK.5 → associar autor
--   para cada genre_id:
--     BOOK.6 → validar género
--     BOOK.7 → associar género
-- COMMIT
-- retornar isbn


-- =============================================
-- ENDPOINT 3 — Modify Copies
-- PUT /sgdproj/updade_copies
-- Apenas ADMIN
-- =============================================
-- Parâmetros: %(isbn)s, %(copies)s

-- COPIES.1 — Verificar se o livro existe
SELECT isbn
FROM books
WHERE isbn = %(isbn)s;

-- COPIES.2 — Verificar cópias atualmente emprestadas
SELECT COUNT(*) AS copies_on_loan
FROM loans
WHERE books_isbn = %(isbn)s
  AND return_date IS NULL;

-- COPIES.3 — Atualizar cópias
UPDATE books
SET copies = %(copies)s
WHERE isbn = %(isbn)s
RETURNING isbn;

-- Erros a tratar:
--   user não é admin        → 400
--   livro não existe        → 400
--   copies < 0              → 400
--   copies < copies_on_loan → 400
--   erro inesperado         → 500

-- Transação completa (pseudocódigo para o Elemento B):
-- BEGIN
--   verificar admin
--   COPIES.1 → se não existe, ROLLBACK + 400
--   COPIES.2 → obter copies_on_loan
--   se copies < copies_on_loan → ROLLBACK + 400
--   COPIES.3 → atualizar
-- COMMIT
-- retornar isbn


-- =============================================
-- ENDPOINT 4 — List Books by Genre
-- GET /sgdproj/list_books_by_genre
-- ADMIN e LIBRARIAN
-- =============================================
-- Parâmetros: %(genre_id)s
-- FIX: ARRAY_AGG(DISTINCT a.name) para evitar duplicados
--      quando o livro tem mais do que 1 autor

-- GENRE.1 — Verificar se o género existe
SELECT genre_id
FROM genres
WHERE genre_id = %(genre_id)s;
-- Se não retornar resultado → 400

-- GENRE.2 — Listar todos os livros do género
SELECT
    b.isbn                                              AS "ISBN",
    b.title                                             AS book_name,
    ARRAY_AGG(DISTINCT a.name)                          AS author,
    b.pages,
    b.copies,
    b.copies - COUNT(l.loan_id) FILTER (
        WHERE l.return_date IS NULL
    )                                                   AS available_copies,
    ARRAY_AGG(DISTINCT g.genre_name)                    AS genres
FROM books b
JOIN books_genres  bg ON bg.books_isbn      = b.isbn
JOIN genres        g  ON g.genre_id         = bg.genres_genre_id
JOIN author_books  ab ON ab.books_isbn      = b.isbn
JOIN author        a  ON a.author_id        = ab.author_author_id
LEFT JOIN loans    l  ON l.books_isbn       = b.isbn
WHERE b.isbn IN (
    SELECT books_isbn
    FROM books_genres
    WHERE genres_genre_id = %(genre_id)s
)
GROUP BY b.isbn, b.title, b.pages, b.copies
ORDER BY b.title;

-- Erros a tratar:
--   user não é admin nem librarian → 400
--   género não existe              → 400
--   erro inesperado                → 500


-- =============================================
-- ENDPOINT 5 — Find Book by Name
-- GET /sgdproj/find_book_by_name
-- ADMIN e LIBRARIAN
-- =============================================
-- Parâmetros: %(book_name)s
-- FIX: ARRAY_AGG(DISTINCT a.name) para evitar duplicados

-- NAME.1 — Procurar livro pelo nome (parcial, case-insensitive)
SELECT
    b.isbn                                              AS "ISBN",
    b.title                                             AS book_name,
    ARRAY_AGG(DISTINCT a.name)                          AS author,
    b.pages,
    b.copies,
    b.copies - COUNT(l.loan_id) FILTER (
        WHERE l.return_date IS NULL
    )                                                   AS available_copies,
    ARRAY_AGG(DISTINCT g.genre_name)                    AS genres
FROM books b
JOIN books_genres  bg ON bg.books_isbn  = b.isbn
JOIN genres        g  ON g.genre_id     = bg.genres_genre_id
JOIN author_books  ab ON ab.books_isbn  = b.isbn
JOIN author        a  ON a.author_id    = ab.author_author_id
LEFT JOIN loans    l  ON l.books_isbn   = b.isbn
WHERE b.title ILIKE '%' || %(book_name)s || '%'
GROUP BY b.isbn, b.title, b.pages, b.copies
ORDER BY b.title;

-- Erros a tratar:
--   user não é admin nem librarian → 400
--   book_name em falta             → 400
--   erro inesperado                → 500


-- =============================================
-- ENDPOINT 6 — Find Book by ISBN
-- GET /sgdproj/find_book_by_isbn
-- ADMIN e LIBRARIAN
-- =============================================
-- Parâmetros: %(isbn)s
-- FIX: ARRAY_AGG(DISTINCT a.name) para evitar duplicados

-- ISBN.1 — Procurar livro pelo ISBN (pesquisa exata)
SELECT
    b.isbn                                              AS "ISBN",
    b.title                                             AS book_name,
    ARRAY_AGG(DISTINCT a.name)                          AS author,
    b.pages,
    b.copies,
    b.copies - COUNT(l.loan_id) FILTER (
        WHERE l.return_date IS NULL
    )                                                   AS available_copies,
    ARRAY_AGG(DISTINCT g.genre_name)                    AS genres
FROM books b
JOIN books_genres  bg ON bg.books_isbn  = b.isbn
JOIN genres        g  ON g.genre_id     = bg.genres_genre_id
JOIN author_books  ab ON ab.books_isbn  = b.isbn
JOIN author        a  ON a.author_id    = ab.author_author_id
LEFT JOIN loans    l  ON l.books_isbn   = b.isbn
WHERE b.isbn = %(isbn)s
GROUP BY b.isbn, b.title, b.pages, b.copies;

-- Erros a tratar:
--   user não é admin nem librarian → 400
--   ISBN não existe                → 400
--   erro inesperado                → 500