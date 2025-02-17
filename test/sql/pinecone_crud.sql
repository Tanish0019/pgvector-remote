-- SETUP
-- suppress output
\o /dev/null
-- logging level
SET client_min_messages = 'notice';
-- flush each vector individually
SET remote.vectors_per_request = 1;
SET remote.requests_per_batch = 1;
-- disable flat scan to force use of the index
SET enable_seqscan = off;
-- Testing database is responsible for initializing the mock table with 
-- SELECT remote_create_mock_table(); 
-- CREATE TABLE
DROP TABLE IF EXISTS t;
CREATE TABLE t (id int, val vector(3));
\o

-- CREATE INDEX
INSERT INTO remote_mock (url_prefix, method, response)
VALUES ('https://api.pinecone.io/indexes', 'POST', $${
        "name": "invalid",
        "metric": "euclidean",
        "dimension": 3,
        "status": {
                "ready": true,
                "state": "Ready"
        },
        "host": "fakehost",
        "spec": {
                "serverless": {
                        "cloud": "aws",
                        "region": "us-west-2"
                }
        }
}$$);
-- mock describe index stats
INSERT INTO remote_mock (url_prefix, method, response)
VALUES ('https://fakehost/describe_index_stats', 'GET', '{"namespaces":{},"dimension":3,"indexFullness":0,"totalVectorCount":0}');
-- create index
CREATE INDEX i2 ON t USING remote (val) WITH (spec = '{"serverless":{"cloud":"aws","region":"us-west-2"}}');
-- CREATE INDEX i2 ON t USING remote (val) WITH (host = 'fakehost');



-- INSERT INTO TABLE
-- mock upsert
INSERT INTO remote_mock (url_prefix, method, response)
VALUES ('https://fakehost/vectors/upsert', 'POST', '{"upsertedCount":1}');
-- insert into table
INSERT INTO t (id, val) VALUES (1, '[1,0,0]');
INSERT INTO t (id, val) VALUES (2, '[2,0,0]');
INSERT INTO t (id, val) VALUES (3, '[3,0,0]');
INSERT INTO t (id, val) VALUES (4, '[4,0,0]');

SELECT *, ctid FROM t;
-- SELECT FROM TABLE
-- mock query
INSERT INTO remote_mock (url_prefix, method, response)
VALUES ('https://fakehost/query', 'POST', $${
        "results":      [],
        "matches":      [{
                        "id":   "000000000001",
                        "score":        2,
                        "values":       []
                }],
        "namespace":    "",
        "usage":        {
                "readUnits":    5
        }
}$$);
-- mock fetch
INSERT INTO remote_mock (url_prefix, method, response)
VALUES ('https://fakehost/vectors/fetch', 'GET', $${
        "code": 3,
        "message":      "No IDs provided for fetch query",
        "details":      []
}$$);
-- select from table
SELECT id,val,val<->'[1,1,1]' as dist FROM t ORDER BY val <-> '[1, 1, 1]';

-- UPDATE A TUPLE AND SELECT FROM TABLE
-- this will trigger an insert, we'll reuse mock upsertedCount:1
UPDATE t SET val = '[1, 1, 1]' WHERE id = 1;
-- this will trigger a query and a fetch request, we'll reuse the mock responses
SELECT id,val,val<->'[1,1,1]' as dist FROM t ORDER BY val <-> '[1,1,1]'; 
\q


-- DELETE AND QUERY FROM TABLE
DELETE FROM t WHERE id = 1;
-- this will trigger a query and a fetch request, we'll reuse the mock responses
SELECT id,val,val<->'[1,1,1]' as dist FROM t ORDER BY val <-> '[1,1,1]';

DROP TABLE t;
