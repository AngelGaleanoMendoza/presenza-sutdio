# Usuarios del panel · Presenza Studio

Quién entra al panel, qué ve cada quien, y cómo agregar a alguien nuevo.

## Cómo se entra

En el sitio: **triple toque** sobre "Reservar" del menú (o abrir la dirección
terminada en `#admin`). Se pide **usuario** y **contraseña**.

La contraseña **no está escrita en la página**: la verifica Supabase. Por eso
cada persona necesita su propia cuenta creada en el Dashboard.

---

## Los usuarios de hoy

### Acceso completo — ven y hacen todo

| Usuario  | Persona          | Rol         |
|----------|------------------|-------------|
| `jimena` | Jimena           | Dueña       |
| `laura`  | Laura Galdámez   | Recepción   |
| `carlos` | Carlos González  | Co-fundador |

Ven las 6 pestañas: **Hoy, Calendario, Reportes, Horarios, Suscriptoras y
Eventos**. Pueden confirmar y rechazar pagos, eliminar reservas, agendar
alumnas, pasar lista, cambiar el horario semanal, cancelar clases sueltas,
activar planes y ver el dinero del día, la semana y el mes.

### Acceso de coach — solo sus propias clases

| Usuario     | Persona                    |
|-------------|----------------------------|
| `carmen`    | María Del Carmen Somarriba |
| `alejandra` | Alejandra Mondragón        |
| `gladys`    | Gladys Pastora             |
| `yeni`      | Yeni Noreña                |

Ven solo **Hoy, Calendario y Horarios**, y dentro de esas pestañas solo las
clases donde ellas aparecen como instructoras. Sirve para pasar lista. **No**
ven reportes de dinero ni la lista de suscriptoras.

> Ojo, para que quede claro: esa separación es del panel, no de la base de
> datos. Una coach con su usuario tiene, a nivel técnico, el mismo permiso de
> lectura que las demás; lo que la limita es la pantalla. Es adecuado para
> repartir el trabajo entre gente de confianza, pero no es una caja fuerte
> contra alguien que quiera saltársela a propósito. Si en algún momento hace
> falta que sí lo sea, se puede cerrar del lado de la base.

---

## Crear la cuenta de una persona nueva

Son dos pasos: uno en Supabase (la contraseña) y otro en el código (el
usuario). **Los dos son necesarios**: sin el primero no puede entrar, sin el
segundo el panel no reconoce el usuario.

### 1 · Crear la cuenta en Supabase

1. Entrar a **supabase.com** → el proyecto de Presenza.
2. Menú izquierdo → **Authentication** → **Users**.
3. Botón **Add user** → **Create new user**.
4. Llenar así:
   - **Email**: el usuario + `@presenza.auth`
     (por ejemplo `laura@presenza.auth` — es un correo interno, no tiene que
     existir de verdad ni recibir nada)
   - **Password**: la contraseña que va a usar esa persona
   - **Auto Confirm User**: **activado** ✅ (si queda apagado, la cuenta pide
     confirmar un correo que nunca va a llegar y no se puede entrar)
5. **Create user**.

### 2 · Agregarla en el código

En `index.html`, buscar `STAFF_TOTAL` (acceso completo) o `COACHES` (solo sus
clases) y agregar una línea:

```js
const STAFF_TOTAL = [
  { usuario:'jimena', nombre:'Jimena',          rol:'Dueña'       },
  { usuario:'laura',  nombre:'Laura Galdámez',  rol:'Recepción'   },
  { usuario:'carlos', nombre:'Carlos González', rol:'Co-fundador' },
  // nueva persona aquí ↓
  { usuario:'ana',    nombre:'Ana Pérez',       rol:'Recepción'   },
];
```

El `usuario` tiene que ser **igual** a lo que va antes de `@presenza.auth` en
Supabase, en minúsculas y sin espacios ni tildes.

Después subir el cambio y esperar 2–3 minutos a que se publique.

---

## Quitarle el acceso a alguien

Basta con **borrar su cuenta en Supabase** (Authentication → Users → los tres
puntos → Delete user). Desde ese momento no puede entrar, aunque su nombre
siga en el código. Para dejarlo limpio, quitar también su línea de
`STAFF_TOTAL` o `COACHES`.

## Cambiar una contraseña

Supabase → **Authentication** → **Users** → los tres puntos junto a la
persona → **Reset password** (o **Edit user** para escribirla directamente).
No hay que tocar el código para esto.

---

## Si alguien no puede entrar

1. **"Usuario no reconocido"** → el usuario no está en el código, o está mal
   escrito. Revisar `STAFF_TOTAL` / `COACHES`.
2. **"Usuario o contraseña incorrectos"** → la cuenta no existe en Supabase,
   el correo no coincide exactamente, o la contraseña está mal. Revisar
   Authentication → Users.
3. **Entra pero no ve datos / dice "permission denied"** → a la base le falta
   correr `supabase-reparacion-total.sql` (Supabase → SQL Editor → pegar todo
   → Run).
4. **Se ve raro o falta algo que ya se arregló** → el navegador guardó una
   copia vieja. La página se actualiza sola, pero se puede forzar con
   `Ctrl + Shift + R`. La versión en uso aparece junto a la fecha dentro del
   panel y abajo en la ventana de acceso.

Para revisar todo el sistema de una sola vez, abrir la dirección del sitio
terminada en **`/diagnostico.html`**: prueba solo y pinta cada cosa en verde
o rojo.
