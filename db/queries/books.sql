-- =============================================
-- Library Management System
-- Data Management Systems Project 2025/2026
-- QUERIES — books.sql
-- Endpoints cobertos:
--   2. Add Book          (POST /sgdproj/book)
--   3. Modify Copies     (PUT  /sgdproj/updade_copies)
-- =============================================
-- NOTAS PARA O ELEMENTO B (API):
--   - Todos os parâmetros indicados com %(param)s
--     são passados via psycopg2 (nunca concatenar strings!)
--   - Cada endpoint é uma transação — usar BEGIN/COMMIT
--   - Em caso de erro fazer ROLLBACK
--   - Autenticação deve ser verificada antes de
--     executar a query principal (ver AUTH abaixo)
-- =============================================


-- =============================================
-- AUTENTICAÇÃO (usar em TODOS os endpoints)
-- =============================================
-- Verificar username + password e obter o user_id e tipo
-- Executar ANTES de qualquer operação
-- Parâmetros: %(username)s, %(password)s

-- AUTH.1 — Verificar credenciais e obter user_id
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
-- Guardar user_type para verificar permissões


-- =============================================
-- ENDPOINT 1 — Register User
-- POST /sgdproj/user
-- =============================================
-- Parâmetros: %(username)s, %(email)s, %(password)s, %(user_type)s
-- user_type pode ser 'reader' ou 'librarian'

-- REG.1 — Inserir na tabela users
INSERT INTO users (username, email, password, created_at)
VALUES (%(username)s, %(email)s, %(password)s, NOW())
RETURNING user_id;

-- REG.2a — Se user_type = 'reader', inserir na tabela reader
-- Usar o user_id retornado pelo REG.1
INSERT INTO reader (users_user_id, n_estudante)
VALUES (%(user_id)s, %(n_estudante)s);

-- REG.2b — Se user_type = 'librarian', inserir na tabela librarian
INSERT INTO librarian (users_user_id, n_mec)
VALUES (%(user_id)s, %(n_mec)s);

-- Erros a tratar:
--   username já existe    → 400 (unique constraint users_username)
--   email já existe       → 400 (unique constraint unique_email)
--   erro inesperado       → 500


-- =============================================
-- ENDPOINT 2 — Add Book
-- POST /sgdproj/book
-- Apenas ADMIN pode executar
-- =============================================
-- Parâmetros principais:
--   %(isbn)s, %(title)s, %(description)s,
--   %(pages)s, %(copies)s
--   %(author_name)s      → nome do autor
--   %(genres)s           → lista de genre_id (tratar em Python)

-- BOOK.1 — Verificar se o ISBN já existe
SELECT isbn FROM books WHERE isbn = %(isbn)s;
-- Se retornar resultado → 400 (livro já existe)

-- BOOK.2 — Verificar se o autor já existe (pelo nome)
SELECT author_id FROM author WHERE name = %(author_name)s;
-- Se não existir → executar BOOK.3
-- Se existir     → guardar author_id e saltar para BOOK.4

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

-- BOOK.6 — Verificar se os géneros existem
-- Executar para cada genre_id na lista recebida
SELECT genre_id FROM genres WHERE genre_id = %(genre_id)s;
-- Se algum não existir → ROLLBACK + 400 (género inválido)

-- BOOK.7 — Associar géneros ao livro
-- Executar para cada genre_id validado no passo anterior
INSERT INTO books_genres (books_isbn, genres_genre_id)
VALUES (%(isbn)s, %(genre_id)s);

-- Erros a tratar:
--   user não é admin      → 400 (permissão negada)
--   ISBN já existe        → 400
--   copies < 1            → 400 (pelo menos 1 cópia obrigatória)
--   pages <= 0            → 400 (check constraint)
--   género não existe     → 400
--   lista géneros vazia   → 400
--   erro inesperado       → 500

-- Transação completa (pseudocódigo para o Elemento B):
-- BEGIN
--   BOOK.1 → se existe, ROLLBACK + 400
--   BOOK.2 → se não existe autor, BOOK.3
--   BOOK.4 → inserir livro
--   BOOK.5 → associar autor
--   para cada genre_id:
--     BOOK.6 → validar género
--     BOOK.7 → associar género
-- COMMIT
-- retornar ISBN


-- =============================================
-- ENDPOINT 3 — Modify Copies
-- PUT /sgdproj/updade_copies
-- Apenas ADMIN pode executar
-- =============================================
-- Parâmetros: %(isbn)s, %(copies)s

-- COPIES.1 — Verificar se o livro existe
SELECT isbn FROM books WHERE isbn = %(isbn)s;
-- Se não retornar resultado → 400 (livro não existe)

-- COPIES.2 — Verificar quantas cópias estão atualmente emprestadas
-- (return_date IS NULL → empréstimo ativo)
SELECT COUNT(*) AS copies_on_loan
FROM loans
WHERE books_isbn = %(isbn)s
  AND return_date IS NULL;

-- COPIES.3 — Atualizar cópias
-- Só executar se %(copies)s >= copies_on_loan (verificar em Python)
-- Se copies < copies_on_loan → 400 (não pode reduzir abaixo dos empréstimos ativos)
UPDATE books
SET copies = %(copies)s
WHERE isbn = %(isbn)s
RETURNING isbn;

-- Erros a tratar:
--   user não é admin      → 400 (permissão negada)
--   livro não existe      → 400
--   copies < 0            → 400 (check constraint)
--   copies < on_loan      → 400 (não pode reduzir abaixo dos empréstimos ativos)
--   erro inesperado       → 500

-- Transação completa (pseudocódigo para o Elemento B):
-- BEGIN
--   COPIES.1 → se não existe, ROLLBACK + 400
--   COPIES.2 → obter copies_on_loan
--   se %(copies)s < copies_on_loan → ROLLBACK + 400
--   COPIES.3 → atualizar
-- COMMIT
-- retornar ISBN