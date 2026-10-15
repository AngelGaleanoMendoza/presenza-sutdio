const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { PGlite } = require(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const table = name => read(name === 'reservas' ? 'supabase-reservas.sql' : 'supabase-datos-compartidos.sql')
  .match(new RegExp('create table if not exists ' + name + ' \\([\\s\\S]*?\\n\\);'))[0];

(async () => {
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon; create role authenticated;
      create schema auth;
      create function auth.role() returns text language sql as $$ select coalesce(current_setting('test.role', true), 'anon') $$;
      ${table('suscriptoras')}
      ${table('reservas')}
      ${table('clases_especiales')}
      alter table suscriptoras add pendiente_estado text default 'espera', add pendiente_ref text;
      create unique index reservas_mat_unico on reservas(slot_key,lugar);
      alter table reservas enable row level security;
      create policy reservas_insert on reservas for insert with check(true);
      grant usage on schema public,auth to anon,authenticated;
      grant insert on reservas to anon,authenticated;
      grant usage on all sequences in schema public to anon,authenticated;
    `);
    const base = read('supabase-reparacion-total.sql');
    for (const name of ['norm_tel', 'norm_nombre', 'nombre_coincide', 'hoy_ni', 'solicitar_plan_publico']) {
      const match = base.match(new RegExp('create or replace function ' + name + '\\([\\s\\S]*?\\$\\$;'));
      assert(match, name);
      await db.exec(match[0]);
    }
    await db.exec(read('supabase-compras-y-reservas.sql'));
    await db.exec(read('supabase-compras-y-reservas.sql'));
    const asAnon = async action => {
      await db.exec('set role anon');
      try { return await action(); }
      finally { await db.exec('reset role'); }
    };
    const purchase = (plan, method) => asAnon(() => db.query('select solicitar_compra_publica($1,$2,$3,$4,$5,$6) as id',
      ['Ana Perez', 'ana@example.com', '88888888', '', plan, method]));
    const first = await purchase('plan5', 'transferencia');
    assert.equal((await purchase('plan5', 'transferencia')).rows[0].id, first.rows[0].id);
    await assert.rejects(() => purchase('plan5', 'efectivo'), /no válido/);
    await assert.rejects(() => purchase('plan10', 'link_bac'), /compra pendiente/);
    const sub = (await db.query('select * from suscriptoras')).rows[0];
    assert.equal(sub.pendiente_metodo, 'transferencia');
    assert.equal(sub.activa, false);
    assert.equal(sub.clases_restantes, 0);
    assert.equal((await db.query('select count(*)::int as n from reservas')).rows[0].n, 0);
    let ts = 0;
    const reserve = (lugar, extras = {}) => asAnon(() => db.query('select reservar_con_plan($1)', [JSON.stringify({
      slot_key: 'slot', clase: 'pilates', fecha: new Date().toISOString().slice(0,10), hora: '10:00',
      ts: ++ts, nombre: 'Ana Perez', email: 'ana@example.com', tel: '88888888', lugar,
      metodo: 'Pago confirmado manipulado', pago_ok: true, clase_descontada: false, ...extras
    })]));
    await assert.rejects(() => reserve(1), /membresía activa/);
    await db.exec(`update suscriptoras set activa=true, plan='plan5', clases_restantes=2,
      fecha_vence=hoy_ni()+30, pendiente_plan=null;`);
    await reserve(1);
    let balance = (await db.query('select clases_restantes,clases_usadas from suscriptoras')).rows[0];
    assert.deepEqual(balance, { clases_restantes: 1, clases_usadas: 1 });
    const reservation = (await db.query('select * from reservas')).rows[0];
    assert.equal(reservation.clase_descontada, true);
    assert.equal(reservation.metodo, '💎 Suscripción · plan5');
    await assert.rejects(() => reserve(1), /duplicate key/);
    assert.equal((await db.query('select clases_restantes from suscriptoras')).rows[0].clases_restantes, 1);
    await reserve(2);
    await assert.rejects(() => reserve(3), /membresía activa/);
    await db.exec(`update suscriptoras set plan='ilimit1', clases_restantes=1000;`);
    await reserve(3);
    assert.equal((await db.query('select clases_restantes from suscriptoras')).rows[0].clases_restantes, 1000);
    await db.exec(`update suscriptoras set fecha_vence=hoy_ni()-1;`);
    await assert.rejects(() => reserve(4), /membresía activa/);
    await db.exec(`update suscriptoras set fecha_vence=hoy_ni()+1;`);
    await assert.rejects(() => reserve(4, { fecha: '2099-01-01' }), /membresía activa/);
    await assert.rejects(() => reserve(4, { email: 'otra@example.com', tel: '77777777', nombre: 'Otra' }), /membresía activa/);
    await db.exec(`insert into clases_especiales(id,clase,fecha,hora,precio) values('free','pilates',current_date,'10:00',0);
      update suscriptoras set activa=false;`);
    await assert.rejects(() => reserve(4), /membresía activa/);
    await db.exec(`update suscriptoras set activa=true;`);
    await reserve(4);
    assert.equal((await db.query('select clase_descontada from reservas where lugar=4')).rows[0].clase_descontada, false);
    console.log('OK: SQL idempotente, método persistido, compra sin cupo, plan pendiente, saldo, último crédito, rollback por mat ocupado, ilimitada, vencimiento, identidad y clase gratuita con plan activo.');
  } finally { await db.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
