SELECT json('{"a":[1,2,{"b":null}],"c":"x"}');
SELECT json_extract('{"a":[1,2,{"b":3}]}', '$.a[2].b');
SELECT json_group_array(value) FROM json_each('[3,1,2]');
SELECT json_set('{"a":1}', '$.b', json_array(1,2,3));
SELECT jsonb_pretty(jsonb('{"k":[true,false]}'));
SELECT printf('%d %s %5.2f %q', 42, 'str', 3.14159, 'it''s');
SELECT date('2024-02-29','+1 year'), strftime('%s','2000-01-01'), typeof(1e3), hex(randomblob(4)), abs(-7), round(2.567,1), instr('abcdef','cd'), substr('abcdef',2,3);
SELECT CAST('12abc' AS INTEGER), 9223372036854775807+1, 1/0, '5'+'6', likely(1), coalesce(NULL,2);
