# qb-aipolice

AI Police para Qbox/QBX, QBCore y Standalone/vMenu.

## Prueba rápida
1. Reinicia `qb-aipolice`.
2. Como policía de turno, abre F6 o `/aipolice`.
3. Selecciona un `NPC Civil / Sospechoso` en OBJETIVO.
4. Usa Parada de tráfico: debe salir una patrulla con oficial visible, llegar al NPC, apagar sirena y bajar el oficial.
5. Usa Persecución: la patrulla debe perseguir al NPC con sirena.
6. Usa Transporte / arresto: la unidad persigue, baja y procesa el NPC.
7. Usa Respaldo/Patrulla sin objetivo: las unidades van a tu zona.
8. Pulsa Retirar unidades para limpiar las unidades creadas por el recurso.
9. Para wanted automático: prueba 1 estrella primero; debe llegar solo una patrulla. Al subir a 3+ estrellas se agregan unidades y persecución. Al bajar a 0 se limpian.

El NUI conserva el objetivo seleccionado mientras la lista de NPC se actualiza.


## v2.8.0 — AI Police execution fix
- Las unidades creadas desde el menú ya no se quedan sin tarea después de llegar.
- `backup`: responde y mantiene una posición alrededor del policía.
- `patrol`: patrulla de forma autónoma y puede reaccionar a amenazas cercanas.
- `investigate`: llega a la zona, permanece investigando y luego pasa a patrulla.
- `pursuit`, `trafficStop`, `tactical`, `military` y `transport` refrescan sus tareas si GTA las interrumpe.
- Las unidades manuales pueden reaccionar automáticamente al wanted del jugador cuando el nivel llega a 3+.
- Las acciones de sospechoso esperan a que el agente llegue físicamente al objetivo antes de ejecutarse.
- Se añadieron estados y watchdog para evitar policías visibles pero inactivos.
- Nueva configuración `Config.AutonomousPolice`.


### v3.1.28 - Respuesta táctica a robos

La IA autónoma ahora puede reaccionar a robos de QBOX/QBX. La respuesta de robo es independiente del sistema de órdenes del menú: crea unidades tácticas, llegan en patrulla, se bajan, buscan al sospechoso, arrestan si se entrega/no está disparando y entran en combate si el sospechoso dispara o hiere a un agente. Se escuchan `qbx_jewelery`, `qbx_bankrobbery` y alertas policiales comunes sin modificar esos recursos.
