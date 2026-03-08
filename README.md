# DMSP Library API

REST API for a library management system built with Python and PostgreSQL.

## Project Overview

This project was developed for the DMSP course and consists of a RESTful API for managing a library system.

The system supports the management of:

- users
- books
- genres
- loans
- reviews

The API is designed to allow different user roles to interact with the system according to their permissions.

## Main Features

- User registration and authentication
- Book creation and copy management
- Search books by title, genre, or ISBN
- View available books
- Borrow and return books
- Submit and update reviews
- View loan history
- Generate reports and rankings

## User Roles

The system includes three types of users:

- **Administrator**
  - add books
  - update the number of copies
  - create other administrators

- **Librarian**
  - view loans
  - check book loan history
  - generate reports

- **Reader**
  - browse the catalog
  - borrow books
  - return books
  - submit reviews

## Technologies

- **Python**
- **PostgreSQL**
- **REST API**
- **JSON**
- **Postman**
- **Git/GitHub**

## Project Structure

```bash
dmsp-library-api/
│── app/
│   │── api/
│   │── db/
│   │── services/
│   │── utils/
│   └── main.py
│
│── docs/
│── postman/
│── sql/
│── tests/
│── README.md
│── requirements.txt
└── .gitignore
