-- =============================================
-- Library Management System
-- Data Management Systems Project 2025/2026
-- QUERIES — reader.sql
-- Endpoints cobertos:
--   11. Available Books by Genre  (GET  /sgdproj/available_books_by_genre)
--   12. Check Book                (GET  /sgdproj/check_book)
--   13. Borrow Book               (POST /sgdproj/borrow_book)
-- =============================================
-- NOTAS PARA O ELEMENTO B (API):
--   - Parâmetros via %(param)s (nunca concatenar strings!)
--   - Endpoints 11 e 12 são PÚBLICOS (sem autenticação)
--   - Endpoint 13 requer qualquer utilizador autenticado
--     (admin, librarian ou reader)
--   - Endpoint 13 usa transação com SELECT FOR UPDATE
--     para garantir atomicidade em cenários concorrentes
-- =============================================


-- =============================================
-- ENDPOINT 11 — Available Books by Genre
-- GET /sgdproj/available_books_by_genre
-- PÚBLICO (sem autenticação)
-- =============================================
-- Parâmetros: %(genre_id)s
-- Lista livros com cópias disponíveis (available_copies > 0)
-- num dado género. Rating = mediana das avaliações (PERCENTILE_CONT).

-- AVAIL.1 — Verificar se o género existe
SELECT genre_id
FROM genres
WHERE genre_id = %(genre_id)s;
-- Se não retornar resultado → 400

-- AVAIL.2 — Livros disponíveis no género
SELECT
    b.isbn,
    b.title                                                      AS book_name,
    b.copies,
    b.copies - COUNT(l.loan_id) FILTER (
        WHERE l.return_date IS NULL
    )                                                            AS available_copies,
    b.description                                                AS book_description,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.rating)       AS raiting
FROM books         b
JOIN books_genres  bg ON bg.books_isbn  = b.isbn
LEFT JOIN loans    l  ON l.books_isbn   = b.isbn
LEFT JOIN reviews  r  ON r.books_isbn   = b.isbn
WHERE bg.genres_genre_id = %(genre_id)s
GROUP BY b.isbn, b.title, b.copies, b.description
HAVING b.copies - COUNT(l.loan_id) FILTER (
    WHERE l.return_date IS NULL
) > 0
ORDER BY b.title;

-- Erros a tratar:
--   genre_id em falta    → 400
--   género não existe    → 400
--   erro inesperado      → 500
-- Resultado vazio (todos os livros do género estão emprestados)
--   → retornar results: []


-- =============================================
-- ENDPOINT 12 — Check Book
-- GET /sgdproj/check_book
-- PÚBLICO (sem autenticação)
-- =============================================
-- Parâmetros: %(ISBN)s
-- Retorna informação do livro + rating médio + lista de reviews.
-- Implementado com duas queries separadas (ver Elemento B).

-- CHECK.1 — Obter título e rating médio
SELECT
    b.title,
    AVG(r.rating) AS overall_rating
FROM books    b
LEFT JOIN reviews r ON r.books_isbn = b.isbn
WHERE b.isbn = %(ISBN)s
GROUP BY b.title;
-- Se não retornar resultado → 400 (livro não existe)

-- CHECK.2 — Listar todas as reviews do livro (mais recentes primeiro)
SELECT
    rating,
    comment
FROM reviews
WHERE books_isbn = %(ISBN)s
ORDER BY review_date DESC;

-- Erros a tratar:
--   ISBN em falta        → 400
--   livro não existe     → 400
--   erro inesperado      → 500
-- overall_rating NULL → livro sem reviews (retornar null)


-- =============================================
-- ENDPOINT 13 — Borrow Book
-- POST /sgdproj/borrow_book
-- ADMIN, LIBRARIAN e READER (qualquer autenticado)
-- =============================================
-- Parâmetros: %(ISBN)s, %(user_id)s
-- Cria um empréstimo, com as seguintes verificações em sequência:
--   1. Livro existe (com lock FOR UPDATE)
--   2. Há cópias disponíveis
--   3. Utilizador não ultrapassou limite de 5 empréstimos simultâneos
--   4. Utilizador não tem já este livro emprestado
--
-- ESTRATÉGIA DE CONCORRÊNCIA — SELECT FOR UPDATE:
--   O lock na linha do livro garante que o par
--   "verificar cópias → inserir empréstimo" é atómico.
--   Transações concorrentes para o mesmo ISBN ficam em espera
--   até ao COMMIT/ROLLBACK desta transação, eliminando a
--   race condition que poderia resultar em available_copies < 0.
--   A constraint unique_active_loan serve de segunda linha de defesa.
--
-- Transação completa (pseudocódigo para o Elemento B):
-- BEGIN
--   BORROW.1 → bloquear linha do livro (FOR UPDATE); se não existe → ROLLBACK + 400
--   BORROW.2 → contar empréstimos ativos do livro
--              se available_copies <= 0 → ROLLBACK + 400
--   BORROW.3 → contar empréstimos ativos do utilizador
--              se COUNT >= 5 → ROLLBACK + 400
--   BORROW.4 → verificar empréstimo duplicado
--              se existe → ROLLBACK + 400
--   BORROW.5 → inserir empréstimo
-- COMMIT

-- BORROW.1 — Verificar livro e adquirir lock de escrita
SELECT copies
FROM books
WHERE isbn = %(ISBN)s
FOR UPDATE;
-- Se não retornar resultado → 400

-- BORROW.2 — Contar cópias atualmente em empréstimo
SELECT COUNT(*)
FROM loans
WHERE books_isbn    = %(ISBN)s
  AND return_date IS NULL;
-- available_copies = copies (BORROW.1) - COUNT → se <= 0 → 400

-- BORROW.3 — Verificar limite de 5 empréstimos simultâneos por utilizador
SELECT COUNT(*)
FROM loans
WHERE users_user_id = %(user_id)s
  AND return_date IS NULL;
-- Se COUNT >= 5 → 400

-- BORROW.4 — Verificar se o utilizador já tem este livro emprestado
SELECT loan_id
FROM loans
WHERE users_user_id = %(user_id)s
  AND books_isbn    = %(ISBN)s
  AND return_date IS NULL;
-- Se retornar resultado → 400

-- BORROW.5 — Registar o empréstimo
INSERT INTO loans (books_isbn, users_user_id)
VALUES (%(ISBN)s, %(user_id)s);

-- Erros a tratar:
--   credenciais inválidas              → 401
--   ISBN ou user_id em falta           → 400
--   livro não existe                   → 400
--   sem cópias disponíveis             → 400
--   limite de 5 empréstimos atingido   → 400
--   utilizador já tem o livro          → 400
--   erro inesperado (ex: violação da
--     constraint unique_active_loan)   → 500


-- =============================================
-- ENDPOINT 14 — Submit Review
-- POST /sgdproj/submit_review
-- READER (qualquer utilizador autenticado que tenha emprestado o livro)
-- =============================================
-- Parâmetros: %(user_id)s, %(ISBN)s, %(rating)s, %(comment)s
-- Cria uma review para um livro. Restrições:
--   - O utilizador tem de ter emprestado o livro pelo menos uma vez
--     (histórico — não precisa de ser um empréstimo activo).
--   - Cada utilizador só pode ter uma review por livro
--     (PK composta: books_isbn + users_user_id).
--   - rating obrigatório entre 1 e 5 (constraint chk_reviews_rating na BD).
--   - comment é opcional (pode ser NULL).

-- Transação completa (pseudocódigo para o Elemento B):
-- BEGIN
--   REV.1 → se livro não existe → ROLLBACK + 400
--   REV.2 → se utilizador nunca emprestou o livro → ROLLBACK + 400
--   REV.3 → se já existe review → ROLLBACK + 400
--   REV.4 → INSERT review
-- COMMIT
-- retornar ISBN + user_id

-- REV.1 — Verificar se o livro existe
SELECT isbn
FROM books
WHERE isbn = %(ISBN)s;
-- Se não retornar resultado → 400

-- REV.2 — Verificar se o utilizador já emprestou o livro (histórico)
SELECT loan_id
FROM loans
WHERE users_user_id = %(user_id)s
  AND books_isbn    = %(ISBN)s
LIMIT 1;
-- Se não retornar resultado → 400 (só se pode rever o que se emprestou)

-- REV.3 — Verificar se já existe uma review deste utilizador para este livro
SELECT 1
FROM reviews
WHERE books_isbn    = %(ISBN)s
  AND users_user_id = %(user_id)s;
-- Se retornar resultado → 400 (a PK também impediria o INSERT, mas assim
--   devolvemos uma mensagem de erro clara em vez de um erro de constraint)

-- REV.4 — Inserir a review
-- review_date fica com o valor DEFAULT NOW() definido no schema
INSERT INTO reviews (rating, comment, books_isbn, users_user_id)
VALUES (%(rating)s, %(comment)s, %(ISBN)s, %(user_id)s);

-- Erros a tratar:
--   credenciais inválidas                   → 401
--   user_id, ISBN ou rating em falta        → 400
--   livro não existe                        → 400
--   utilizador nunca emprestou o livro      → 400
--   review já existe para este utilizador   → 400
--   rating fora do intervalo [1, 5]         → 400
--   erro inesperado (ex: violação da PK)    → 500
