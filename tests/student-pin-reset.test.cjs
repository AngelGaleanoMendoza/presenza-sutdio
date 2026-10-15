const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { PGlite } = require(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const read = f => fs.readFileSync(path.join(__dirname, '..', f), 'utf8');

(async () => {
  for (const m of read('index.html').matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)) new vm.Script(m[1]);
  assert(!/staffPassword|CambioClaveStaff|guardarClaveStaff/.test(read('index.html')));
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon; create role authenticated; create schema auth; create schema extensions;
      create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
      create function auth.role() returns text language sql as $$ select current_setting('test.role',true) $$;
      create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
      create table suscriptoras(id text primary key,nombre text,tel text);
      create table alumnas(id uuid primary key,nombre_completo text,tel text,sub_id text,pin_hash text);
      create table sesiones_alumna(token uuid,alumna_id uuid);
      create function extensions.gen_salt(text) returns text language sql as $$ select 'test-salt' $$;
      create function extensions.crypt(text,text) returns text language sql as $$ select 'test-hash:' || md5($1 || $2) $$;
      grant usage on schema public,auth to anon,authenticated;
      insert into auth.users values
        ('00000000-0000-0000-0000-000000000001','jimena@presenza.auth',now()),
        ('00000000-0000-0000-0000-000000000002','carlos@presenza.auth',now()),
        ('00000000-0000-0000-0000-000000000003','laura@presenza.auth',now()),
        ('00000000-0000-0000-0000-000000000004','carmen@presenza.auth',now());
      insert into suscriptoras values ('SUB-A','Ana Perez','88888888'),('SUB-B','Bea Lopez','77777777');
      insert into alumnas values ('10000000-0000-0000-0000-000000000001','Ana Perez','88888888','SUB-A','old');
    `);
    const base = read('supabase-reparacion-total.sql');
    for (const name of ['norm_tel','norm_nombre','nombre_coincide']) {
      await db.exec(base.match(new RegExp('create or replace function '+name+'\\([\\s\\S]*?\\$\\$;'))[0]);
    }
    await db.exec(read('supabase-restablecer-pin-alumnas.sql'));
    await db.exec(read('supabase-restablecer-pin-alumnas.sql'));
    const reset = async (who, pin='1234', sub='SUB-A') => {
      await db.query("select set_config('test.uid',$1,false),set_config('test.role','authenticated',false)", ['00000000-0000-0000-0000-00000000000'+who]);
      await db.exec('set role authenticated');
      try { return await db.query('select restablecer_pin_alumna_staff($1,$2)',[sub,pin]); }
      finally { await db.exec('reset role'); }
    };
    await assert.rejects(() => reset(4), /Solo Jimena/);
    await assert.rejects(() => reset(1,'123'), /4 dígitos/);
    await assert.rejects(() => reset(1,null), /4 dígitos/);
    await assert.rejects(() => reset(1,'1234','SUB-B'), /todavía no tiene acceso/);
    await db.exec('set role anon');
    await assert.rejects(() => db.query("select restablecer_pin_alumna_staff('SUB-A','1234')"), /permission denied/);
    await db.exec('reset role');
    for (const who of [1,2,3]) {
      await db.exec("insert into sesiones_alumna values('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001')");
      await reset(who);
      assert.equal((await db.query('select count(*)::int n from sesiones_alumna')).rows[0].n,0);
    }
    assert.equal((await db.query('select count(*)::int n from cambios_pin_alumna')).rows[0].n,3);
    const hash = (await db.query('select pin_hash from alumnas')).rows[0].pin_hash;
    assert.match(hash,/^test-hash:/);
    assert.notEqual(hash,'1234');
    await db.exec("update alumnas set sub_id='SUB-B'");
    await assert.rejects(() => reset(1), /otra ficha/);
    await db.exec("update alumnas set sub_id=null,nombre_completo='Otra Persona'");
    await assert.rejects(() => reset(1), /nombre del acceso/);
    await db.exec("update alumnas set nombre_completo='Ana Perez'");
    await reset(1);
    assert.equal((await db.query('select sub_id from alumnas')).rows[0].sub_id,'SUB-A');
    console.log('OK: sintaxis, solo tres cuentas autorizadas, rechazo de coaches y anon, validación del PIN, sesiones cerradas, auditoría y protección contra fichas equivocadas. Crypto sustituida únicamente en esta base temporal.');
  } finally { await db.close(); }
})().catch(e => { console.error(e); process.exitCode=1; });
