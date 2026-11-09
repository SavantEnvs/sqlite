CREATE TABLE t1(a INTEGER PRIMARY KEY, b TEXT, c REAL);
INSERT INTO t1 VALUES(1,'one',1.5),(2,'two',2.5),(3,'three',NULL);
SELECT a, upper(b), c*2 FROM t1 WHERE a>1 ORDER BY b DESC;
UPDATE t1 SET b=b||'!' WHERE c IS NULL;
DELETE FROM t1 WHERE a=2;
SELECT count(*), sum(a), group_concat(b) FROM t1;
