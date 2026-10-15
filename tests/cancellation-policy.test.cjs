const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { PGlite } = require(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const read = f => fs.readFileSync(path.join(__dirname, '..', f), 'utf8');
const token = '10000000-0000-0000-0000-000000000001';

(async () => {
  const html = read('index.html');
  for (const m of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)) new vm.Script(m[1]);
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon; create role authenticated; create schema auth;
      create function auth.role() returns text language sql as $$ select current_setting('test.role',true) $$;
      create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
      create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
      create table alumnas(id uuid primary key,tel text,email text);
      create table sesiones_alumna(token uuid,alumna_id uuid,expira timestamptz);
      create table suscriptoras(id text primary key,tel text,email text,clases_restantes int,clases_usadas int);
      ${read('supabase-reservas.sql').match(/create table if not exists reservas \([\s\S]*?\n\);/)[0]}
      alter table reservas add cancelada timestamptz,add clase_descontada boolean default false;
      grant usage on schema public,auth to anon,authenticated;
      insert into alumnas values('${token}','88888888','ana@example.com');
      insert into sesiones_alumna values('${token}','${token}',now()+interval '1 day');
      insert into suscriptoras values('SUB-A','88888888','ana@example.com',4,1);
      insert into auth.users values
        ('00000000-0000-0000-0000-000000000001','jimena@presenza.auth',now()),
        ('00000000-0000-0000-0000-000000000002','carmen@presenza.auth',now());
    `);
    await db.exec(read('supabase-reparacion-total.sql').match(/create or replace function norm_tel\([\s\S]*?\$\$;/)[0]);
    await db.exec(read('supabase-cancelaciones-tardias.sql'));
    await db.exec(read('supabase-cancelaciones-tardias.sql'));
    let ts = 0;
    const seed = async (interval, method='Suscripcion plan5', charged=true, email='ana@example.com') => {
      const id = ++ts;
      await db.query(`with t as(select now()+$1::interval as start)
        insert into reservas(slot_key,clase,fecha,hora,ts,nombre,email,tel,metodo,clase_descontada)
        select $2,'pilates',(start at time zone 'America/Managua')::date,
        (start at time zone 'America/Managua')::time::text,$3,'Ana',$4,$5,$6,$7 from t`,
        [interval,'slot'+id,id,email,email==='ana@example.com'?'88888888':'77777777',method,charged]);
      return id;
    };
    const cancel = async (id, confirm=false, accept=false) => {
      await db.exec('set role anon');
      try { return (await db.query('select * from cancelar_reserva_alumna($1,$2,$3,$4)',[token,id,confirm,accept])).rows[0]; }
      finally { await db.exec('reset role'); }
    };
    const balance = async () => (await db.query('select clases_restantes as n from suscriptoras')).rows[0].n;
    const fees = async () => (await db.query("select count(*)::int n from penalizaciones_cancelacion where tipo='fee'")).rows[0].n;
    await db.exec('begin');
    const six = await seed('6 hours');
    assert.equal((await cancel(six)).requiere_penalizacion,false);
    assert.equal((await cancel(six,true)).devuelta,true);
    assert.equal(await balance(),5);
    await db.exec('commit');
    const late = await seed('5 hours');
    assert.match((await cancel(late)).mensaje,/deducirá de tu paquete/);
    assert.equal((await cancel(late,true,false)).requiere_penalizacion,true);
    assert.equal(await balance(),5);
    assert.equal((await cancel(late,true,true)).devuelta,false);
    assert.equal(await balance(),5);
    assert.equal((await cancel(late,true,true)).ok,false);
    const unlimited = await seed('1 hour','Suscripcion ilimit1',false);
    assert.match((await cancel(unlimited)).mensaje,/fee de US\$5/);
    assert.equal(await fees(),0);
    assert.equal((await cancel(unlimited,true,false)).ok,false);
    assert.equal(await fees(),0);
    assert.equal((await cancel(unlimited,true,true)).ok,true);
    assert.equal(await fees(),1);
    assert.equal((await cancel(unlimited,true,true)).ok,false);
    assert.equal(await fees(),1);
    const earlyUnlimited = await seed('7 hours','Suscripcion Mensual ilimitado',false);
    assert.equal((await cancel(earlyUnlimited,true)).ok,true);
    assert.equal(await fees(),1);
    assert.equal((await cancel(await seed('-1 hour'),true,true)).ok,false);
    assert.equal((await cancel(await seed('1 hour','Suscripcion plan5',true,'otra@example.com'),true,true)).ok,false);
    const legacy = await seed('2 hours');
    assert.equal((await db.query('select * from cancelar_mi_reserva($1,$2)',[token,legacy])).rows[0].ok,false);
    await db.query("select set_config('test.role','authenticated',false),set_config('test.uid',$1,false)",['00000000-0000-0000-0000-000000000002']);
    await db.exec('set role authenticated');
    await assert.rejects(() => db.query('select * from gestionar_fees_cancelacion()'),/Solo Jimena/);
    await db.exec('reset role');
    await db.query("select set_config('test.uid',$1,false)",['00000000-0000-0000-0000-000000000001']);
    await db.exec('set role authenticated');
    const pending = (await db.query('select * from gestionar_fees_cancelacion()')).rows;
    assert.equal(pending.length,1);
    assert.equal(Number(pending[0].monto_usd),5);
    assert.equal((await db.query('select * from gestionar_fees_cancelacion($1)',[pending[0].id])).rows.length,0);
    await db.exec('reset role');
    const messages = [], calls = [];
    const context = vm.createContext({
      alCancelando:false, AL_TOKEN_KEY:'token', localStorage:{getItem:()=>token},
      confirm: m => { messages.push(m); return true; }, alert() {}, alCargarPanel() {},
      sbRpc: async (fn,args) => {
        calls.push(args);
        return calls.length===1 ? [{ok:true,mensaje:'Confirmar sin penalizacion',requiere_penalizacion:false}]
          : calls.length===2 ? [{ok:false,mensaje:'Fee de US$5. Continuar?',requiere_penalizacion:true}]
          : [{ok:true,mensaje:'Cancelada',devuelta:false}];
      }
    });
    vm.runInContext(html.match(/async function alCancelar\([\s\S]*?\n}/)[0],context);
    await context.alCancelar(1,'Pilates','Hoy');
    assert.equal(messages.length,2);
    assert.equal(calls[1].p_acepta_penalizacion,false);
    assert.equal(calls[2].p_acepta_penalizacion,true);
    console.log('OK: límite exacto de 6 horas, aviso previo, rechazo sin consentimiento, clase sin doble descuento, ilimitada con fee único de US$5, devolución temprana, identidad, pasado, endpoint antiguo, permisos de cobro y nuevo aviso al cruzar el límite.');
  } finally { await db.close(); }
})().catch(e => { console.error(e); process.exitCode=1; });
