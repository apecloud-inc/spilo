CREATE EXTENSION vector;
CREATE TABLE vectors (id integer PRIMARY KEY, value vector(3));
INSERT INTO vectors VALUES (1, '[1,0,0]'), (2, '[0,1,0]'), (3, '[0,0,1]');
CREATE INDEX ON vectors USING hnsw (value vector_l2_ops);
SET enable_seqscan = off;
DO $$
BEGIN
    ASSERT (SELECT extversion = '0.8.7' FROM pg_extension WHERE extname = 'vector');
    ASSERT (SELECT path IS NOT NULL FROM pg_extension_update_paths('vector')
            WHERE source = '0.8.0' AND target = '0.8.7');
    ASSERT (SELECT id FROM vectors ORDER BY value <-> '[1,0,0]' LIMIT 1) = 1;
END;
$$;
DROP INDEX vectors_value_idx;
CREATE INDEX ON vectors USING ivfflat (value vector_l2_ops) WITH (lists = 1);
DO $$
BEGIN
    ASSERT (SELECT id FROM vectors ORDER BY value <-> '[0,1,0]' LIMIT 1) = 2;
END;
$$;

CREATE EXTENSION zhparser;
CREATE TEXT SEARCH CONFIGURATION chinese (PARSER = zhparser);
ALTER TEXT SEARCH CONFIGURATION chinese ADD MAPPING FOR n,v,a,i,e,l WITH simple;
CREATE TABLE documents (content text, search tsvector);
INSERT INTO documents VALUES ('中国数据库技术', to_tsvector('chinese', '中国数据库技术'));
CREATE INDEX ON documents USING gin (search);
DO $$
BEGIN
    ASSERT (SELECT extversion = '2.4' FROM pg_extension WHERE extname = 'zhparser');
    ASSERT (SELECT count(*) > 1 FROM ts_parse('zhparser', '中国数据库技术'));
    ASSERT (SELECT count(*) = 1 FROM documents WHERE search @@ plainto_tsquery('chinese', '数据库'));
    ASSERT NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'sync_zhprs_custom_word()'::regprocedure);
END;
$$;

CREATE ROLE extension_reader;
GRANT SELECT ON documents TO extension_reader;
SET ROLE extension_reader;
DO $$
BEGIN
    ASSERT (SELECT count(*) = 1 FROM documents WHERE search @@ plainto_tsquery('chinese', '数据库'));
    BEGIN
        PERFORM sync_zhprs_custom_word();
        RAISE EXCEPTION 'ordinary role unexpectedly wrote a server dictionary';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
        WHEN raise_exception THEN
            IF SQLERRM <> 'zhparser: cannot resolve data_directory' THEN
                RAISE;
            END IF;
    END;
END;
$$;
RESET ROLE;

-- Verify CDC against the new minor's default output-plugin allowlist.
SHOW output_plugin_libraries;
CREATE TABLE cdc_events (id integer PRIMARY KEY);
CREATE PUBLICATION extension_smoke FOR TABLE cdc_events;
SELECT pg_create_logical_replication_slot('extension_smoke', 'pgoutput');
INSERT INTO cdc_events VALUES (1);
DO $$
BEGIN
    ASSERT (SELECT count(*) > 0 FROM pg_logical_slot_peek_binary_changes(
        'extension_smoke', NULL, NULL, 'proto_version', '1', 'publication_names', 'extension_smoke'));
END;
$$;
SELECT pg_drop_replication_slot('extension_smoke');
DROP PUBLICATION extension_smoke;
