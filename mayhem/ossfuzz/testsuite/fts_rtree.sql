CREATE VIRTUAL TABLE f USING fts5(a, b);
INSERT INTO f VALUES('hello world','foo bar'),('goodbye world','baz');
SELECT rowid, highlight(f,0,'[',']') FROM f WHERE f MATCH 'world' ORDER BY rank;
CREATE VIRTUAL TABLE r USING rtree(id, x0, x1, y0, y1);
INSERT INTO r VALUES(1,0,10,0,10),(2,5,15,5,15);
SELECT id FROM r WHERE x0<=6 AND x1>=6;
CREATE VIRTUAL TABLE g USING fts4(content);
INSERT INTO g VALUES('the quick brown fox');
SELECT snippet(g) FROM g WHERE g MATCH 'quick';
