-- =============================================
-- Library Management System
-- Data Management Systems Project 2025/2026
-- QUERIES — loans.sql
-- Endpoints cobertos:
--    7. Loaned Books        (GET /sgdproj/loaned_books)
--    8. Loaned Book         (GET /sgdproj/loaned_book)
--    9. Top N Loaned Books  (GET /sgdproj/TopLoanedBooks/<N>)
--   10. Top N Loaners       (GET /sgdproj/TopLoaners/<N>)
-- =============================================
-- NOTAS PARA O ELEMENTO B (API):
--   - Parâmetros via %(param)s (nunca concatenar strings!)
--   - N nos endpoints 9 e 10 vem do URL (int), não do body
--   - Autenticação verificada pelo decorator @require_role
--     antes de entrar no endpoint (ver auth.py)
--   - Todos os endpoints requerem role: admin ou librarian
-- =============================================


-- =============================================
-- ENDPOINT 7 — Loaned Books
-- GET /sgdproj/loaned_books
-- ADMIN e LIBRARIAN
-- =============================================
-- Sem parâmetros de entrada.
-- Retorna um registo por empréstimo ativo (return_date IS NULL).
-- Ordenação: data de empréstimo crescente (mais antigos primeiro).

-- LOAN.1 — Listar todos os empréstimos ativos
SELECT
    b.isbn       AS "ISBN",
    b.title      AS book_name,
    u.user_id    AS loaner_id,
    u.username   AS loaner_name,
    l.loan_date
FROM loans l
JOIN books b ON b.isbn    = l.books_isbn
JOIN users u ON u.user_id = l.users_user_id
WHERE l.return_date IS NULL
ORDER BY l.loan_date;

-- Erros a tratar:
--   user não é admin nem librarian → 403
--   erro inesperado                → 500
-- Resultado vazio → retornar results: []


-- =============================================
-- ENDPOINT 8 — Loaned Book
-- GET /sgdproj/loaned_book
-- ADMIN e LIBRARIAN
-- =============================================
-- Parâmetros: %(ISBN)s
-- Retorna o histórico completo de empréstimos de um livro
-- (ativos e devolvidos), do mais recente para o mais antigo.

-- LHIST.1 — Verificar se o livro existe
SELECT isbn
FROM books
WHERE isbn = %(ISBN)s;
-- Se não retornar resultado → 400

-- LHIST.2 — Histórico de empréstimos do livro
SELECT
    u.user_id   AS loaner_id,
    u.username  AS loaner_name,
    l.loan_date
FROM loans l
JOIN users u ON u.user_id = l.users_user_id
WHERE l.books_isbn = %(ISBN)s
ORDER BY l.loan_date DESC;

-- Erros a tratar:
--   user não é admin nem librarian → 403
--   ISBN em falta                  → 400
--   livro não existe               → 400
--   erro inesperado                → 500
-- Resultado vazio (livro nunca emprestado) → retornar results: []


-- =============================================
-- ENDPOINT 9 — Top N Loaned Books
-- GET /sgdproj/TopLoanedBooks/<N>
-- ADMIN e LIBRARIAN
-- =============================================
-- Parâmetros: N (inteiro > 0, passado no URL — não no body)
-- Retorna os N livros com mais empréstimos no histórico completo.
-- NOTA: o campo "rank" NÃO é calculado em SQL — é gerado
--       em Python com enumerate(rows, start=1).

-- TOPB.1 — Validar N (lógica no Elemento B)
--   se N < 1 → 400

-- TOPB.2 — Top N livros mais emprestados
SELECT
    b.isbn                   AS "ISBN",
    b.title                  AS book_name,
    COUNT(l.loan_id)         AS loaned_times,
    MAX(l.loan_date)         AS last_loaned
FROM books b
JOIN loans l ON l.books_isbn = b.isbn
GROUP BY b.isbn, b.title
ORDER BY loaned_times DESC
LIMIT %(n)s;

-- Campos devolvidos ao cliente:
--   ISBN, book_name, loaned_times, last_loaned, rank (via Python)
-- Erros a tratar:
--   user não é admin nem librarian → 403
--   N < 1                          → 400
--   erro inesperado                → 500


-- =============================================
-- ENDPOINT 10 — Top N Loaners
-- GET /sgdproj/TopLoaners/<N>
-- ADMIN e LIBRARIAN
-- =============================================
-- Parâmetros: N (inteiro > 0, passado no URL — não no body)
-- Retorna os N utilizadores com mais empréstimos no histórico.
-- NOTA: last_loaned_book é obtido via subquery correlacionada
--       (executa uma query adicional por linha do resultado).

-- TOPL.1 — Validar N (lógica no Elemento B)
--   se N < 1 → 400

-- TOPL.2 — Top N loaners com mais empréstimos
SELECT
    u.user_id,
    u.username,
    COUNT(l.loan_id)            AS loaned_books_quantity,
    ARRAY_AGG(DISTINCT b.title) AS loaned_books,
    MAX(l.loan_date)            AS last_loaned_book_date,
    (
        SELECT b2.title
        FROM loans l2
        JOIN books b2 ON b2.isbn = l2.books_isbn
        WHERE l2.users_user_id = u.user_id
        ORDER BY l2.loan_date DESC
        LIMIT 1
    )                           AS last_loaned_book
FROM users u
JOIN loans l ON l.users_user_id = u.user_id
JOIN books b ON b.isbn          = l.books_isbn
GROUP BY u.user_id, u.username
ORDER BY loaned_books_quantity DESC
LIMIT %(n)s;

-- Erros a tratar:
--   user não é admin nem librarian → 403
--   N < 1                          → 400
--   erro inesperado                → 500


-- =============================================
-- ENDPOINT 15 — Return Book
-- POST /sgdproj/return_book
-- ADMIN, LIBRARIAN e READER (qualquer autenticado)
-- =============================================
-- Parâmetros: %(user_id)s, %(ISBN)s
-- Marca o empréstimo ativo como devolvido (return_date = hoje).

-- RET.1 — Verificar se existe empréstimo ativo para este utilizador e livro
SELECT loan_id
FROM loans
WHERE users_user_id = %(user_id)s
  AND books_isbn    = %(ISBN)s
  AND return_date IS NULL;
-- Se não retornar resultado → 400 (livro não está em posse do utilizador)

-- RET.2 — Registar devolução
UPDATE loans
SET    return_date = CURRENT_DATE
WHERE  users_user_id = %(user_id)s
  AND  books_isbn    = %(ISBN)s
  AND  return_date IS NULL
RETURNING loan_id;

-- Erros a tratar:
--   credenciais inválidas               → 401
--   user_id ou ISBN em falta            → 400
--   empréstimo ativo não encontrado     → 400
--   erro inesperado                     → 500

-- Transação completa (pseudocódigo para o Elemento B):
-- BEGIN
--   RET.1 → se não existe empréstimo ativo → ROLLBACK + 400
--   RET.2 → UPDATE return_date = CURRENT_DATE
-- COMMIT
-- retornar loan_id


-- =============================================
-- ENDPOINT 16 — Top Genres (últimos 12 meses)
-- GET /sgdproj/TopGenres/<N>
-- ADMIN e LIBRARIAN
-- =============================================
-- Parâmetros: N (inteiro > 0, passado no URL — não no body)
-- Retorna os N géneros com mais empréstimos nos últimos 12 meses.
-- NOTA: um livro com múltiplos géneros conta para cada um deles
--       (comportamento intencional — reflecte popularidade real por género).

-- TOPG.1 — Validar N (lógica no Elemento B)
--   se N < 1 → 400

-- TOPG.2 — Top N géneros mais emprestados nos últimos 12 meses
SELECT
    g.genre_id,
    g.genre_name,
    COUNT(l.loan_id) AS total_loans
FROM genres       g
JOIN books_genres bg ON bg.genres_genre_id = g.genre_id
JOIN loans        l  ON l.books_isbn       = bg.books_isbn
WHERE l.loan_date >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY g.genre_id, g.genre_name
ORDER BY total_loans DESC
LIMIT %(n)s;

-- Erros a tratar:
--   user não é admin nem librarian → 403
--   N < 1                          → 400
--   erro inesperado                → 500
-- Resultado vazio (sem empréstimos nos últimos 12 meses) → results: []
