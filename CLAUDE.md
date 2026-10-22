# Line & Maul

Fantasy ("Mi XV") y Prode de rugby argentino. Dueño: Lucas (habla en español rioplatense, prefiere respuestas cortas).

- `index.html`: todo el sitio (HTML + CSS + JS en un archivo). Se publica solo con GitHub Pages (`.github/workflows/pages.yml`) al hacer push a `main`.
- Base y login: Supabase (`https://srdnktmbipvpvyzguuyk.supabase.co`, publishable key en `index.html`). Esquema en `supabase/` (se corre a mano en el SQL Editor; desde el entorno de Claude no hay acceso de red a Supabase).
- La capa `makeDb()` imita la API vieja (doc/collection/onSnapshot) sobre las tablas: config, fechas, profiles (nombre, equipo, club), equipos y prode (una fila por usuario y fecha; la base bloquea cambios fuera de la fecha abierta), ligas, liga_miembros, admins.
- Datos semanales: Claude sube el JSON a `novedades/<id>.json` y lo agrega a `novedades/index.json` (`{"items":[{"id","titulo","file"}]}`); Lucas lo carga con un toque en Panel Admin ("Novedades para cargar", con Deshacer). Alternativa: pegarlo en Admin → Ajustes → Importar. Usar ids nuevos para cada carga. Formato:
  `{"fechas": {"<id>": {campos que se mezclan en la fecha}}, "config": {"<key>": {campos}}, "borrar_fechas": ["<id>"], "reemplazar_config": false}`
- `datos/inicial.json`: planteles, camisetas y entrenadores 2026 (botón "Cargar datos iniciales").
- Probar sin red: servir la carpeta y reemplazar el script de supabase-js por un mock en memoria.
- Notificaciones push: `scripts/push.mjs` corre cada 15 min (`.github/workflows/push.yml`) con los secretos `VAPID_PRIVATE` y `PUSH_TOKEN` del repo. Tablas y funciones en `supabase/04_notificaciones.sql`. Avisos manuales: Admin → Notificaciones.
- Escala (10k usuarios): cada celular baja solo lo suyo. Las tablas salen del RPC `tabla()` sobre la tabla `puntos`, que calcula el admin desde el navegador al publicar una fecha (`autoRecalc`/`recalcFecha`, firma en `fechas.data.calc`). Insignias con `calc_insignias()`. Métricas con `metricas()`/`mas_elegidos()`. SQL en `supabase/05_escala.sql`. Votos del prode por partido (Métricas): `prode_votos()` en `supabase/06_prode_votos.sql`. Nombre real (en `auth.users` metadata `nombre_real`, solo admin): `nombres_reales()` en `supabase/07_nombres_reales.sql`. Buzón de sugerencias (tabla `sugerencias`, máx. 5 por día por usuario; se leen en Panel Admin → Buzón): `supabase/08_sugerencias.sql`. Fantasy por región: cada fecha tiene `reg` ("cba" = Córdoba, si no Buenos Aires); los puntos van a `puntos.juego` "dt" o "dt_cba" y `tabla()` filtra por región: `supabase/09_fantasy_regiones.sql`.
- Al cargar formaciones: además de marcar titulares ("T"), revisar SIEMPRE el número de cada titular contra sus puestos (1/3 pilar, 2 hooker, 4-5 segunda, 6-8 tercera, 9 medio, 10 apertura, 12-13 centro, 11/14 wing, 15 fullback) y sumarle el puesto (`gs`) si juega fuera del suyo.
- Regiones: Buenos Aires (Fantasy T14; Prode T14 y 1A) y Córdoba (Fantasy y Prode T10, clubes en `T10_CBA`). El inicio abre las regiones tipo acordeón; Tucumán y Litoral figuran "Próximamente".
- Nombres en el sitio: nunca "Top 14" ni "Primera A"; usar siempre **T14** y **1A** (también en placas y textos nuevos).
