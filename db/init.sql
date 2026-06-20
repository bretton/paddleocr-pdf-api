-- Runs once on first Postgres init (empty data dir only).
-- Creates one database for PaddleOCR (plain) and one for Honcho (pgvector).

CREATE DATABASE ocr;
CREATE DATABASE honcho;

-- Honcho requires the pgvector extension on its database.
\connect honcho
CREATE EXTENSION IF NOT EXISTS vector;
