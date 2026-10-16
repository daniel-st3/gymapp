# Investigación para F01–F27 · 16 de octubre de 2026

Fuentes oficiales consultadas sobre Build 10; cambios de Build 11. Las afirmaciones comerciales de terceros no son validaciones de sus algoritmos ni pruebas ejecutadas por nosotros.

## Sesión del Watch y límites físicos (F02/F03/F13/F16)

[Apple: running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions) documenta HKWorkoutSession para ejecución de un entrenamiento y recuperación con el delegate de la extensión. El SDK watchOS 27 instalado contiene `recoverActiveWorkoutSession` y `beginNewActivity`. Little Lift ahora usa una sola sesión real durante el entrenamiento y conserva primero su registro local. Pide permiso para Workouts; no lee historial de Salud ni guarda calorías, frecuencia cardiaca o un entrenamiento inventado en Salud. El experimento de movimiento no puede iniciarse simultáneamente. El registro manual sigue disponible si Salud falla o se deniega.

No se usa WKExtendedRuntimeSession como keepalive ni se inventa una categoría fitness. [Apple: tipos de sesión extendida](https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions). La [guía Return to Clock / Return to App](https://support.apple.com/en-by/guide/watch/apd127ec93ac/27/watchos/27) describe una preferencia del sistema; su disponibilidad para Little Lift y el retorno con muñeca baja requieren observación física. Always On, foreground, runtime y persistencia no son equivalentes. La app no puede forzar brillo continuo.

[Apple: play(_:)](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play(_:)) advierte del gasto de batería y la interrupción de recogida cardiaca durante haptics. Guía de ritmo es un metrónomo optativo, limitado y cancelable; no detección. No hay control ficticio de intensidad ni conteo automático. No se ha medido sensación, latencia física ni consumo.

El prototipo previo de movimiento permanece aislado y apagado por defecto. Antes de considerarlo detector: elegir elevación lateral o curl con configuración y lado de reloj anotados; registrar referencia manual independiente de inicio/final y cada repetición; repetir series lentas/rápidas, pausas y movimientos ajenos; medir falsos positivos, omisiones, error absoluto de conteo, latencia y huecos de muestras por serie. Comparar muñeca alta/baja, haptics activos/inactivos, batería inicial/final y duración de sesión. No existe todavía ese conjunto físico etiquetado ni un resultado estadístico validado. No se entrena un modelo con datos fabricados. La captura anterior de unas decenas de segundos no demuestra una hora de entrenamiento fiable.

## ChatGPT y contexto (F10/F17/F18/F19/F21)

[Apple: Use Apple Intelligence in Shortcuts](https://support.apple.com/en-tj/guide/shortcuts/tpg3vrvwmclv/10.0/ios/27) documenta Extension Model con ChatGPT y pasar la respuesta a otra acción. Little Lift conserva Prepare → Use Model → Save. Prepare entrega solo el contexto elegido, un ID de revisión y esquema; Save exige respuesta válida y correlación; no acepta respuestas canceladas o duplicadas ni cambia el plan sin aceptación. Abrir Atajos se muestra como abierto para continuar, no como análisis completado. La ejecución real depende del dispositivo, Apple Intelligence, extensión, cuenta, región y permisos. El simulador no es prueba de ejecución física desatendida.

[OpenAI: Apps SDK](https://help.openai.com/en/articles/12515353-build-with-the-apps-sdk) y [conexiones MCP](https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt) describen herramientas usadas desde ChatGPT. La guía MCP consultada requiere permisos de cuenta/workspace y conexión HTTPS remota o túnel; indica restricciones de uso web/móvil. Esto no establece una interfaz para que Little Lift escriba externamente en un hilo arbitrario. No se creó servidor, túnel, integración con datos personales ni enrolamiento. No se inspeccionaron cookies o endpoints privados. Un puente desplegado añadiría autenticación, disponibilidad y mantenimiento; no se ofrece como gratis sin demostrarlo.

La ruta de chat existente sigue siendo compartir un informe/contexto y revisar una importación. Es explícita, no automática. La ruta de Atajos recibe contexto independiente; no hereda el chat del gimnasio. No se afirma haber escrito en ese hilo ni haberlo leído. El procesamiento del modelo puede salir del dispositivo aunque no haya API facturada.

[ChatGPT Search](https://help.openai.com/en/articles/9237897-chatgpt-search) puede estar disponible en distintos planes, con límites. No se demostró búsqueda dentro de nuestra ruta Use Model. El contexto pide fuentes oficiales y confirmación si el chat dispone de búsqueda. Una descripción de una máquina no prueba inventario de una sede. El catálogo local de ocho movimientos funciona sin red, sin fotos ni ubicación automática.

## Referencias de producto (F09)

Se identificó **App Bodytech, desarrollador Bodytech, tienda Colombia**, mediante su [ficha oficial](https://apps.apple.com/co/app/app-bodytech/id1571331644), versión publicada 1.9.10 al consultar. Anuncia sesiones diarias, planificación por objetivos y conexión con Salud; las notas mencionan entrenamiento libre y racha. No accedimos a una cuenta de gimnasio ni observamos esas funciones dentro de una sesión real. Las promesas de prescripción inteligente o salud no se adoptan como evidencia técnica.

| Patrón publicado | Decisión concreta en Little Lift | Lo que no se infiere |
|---|---|---|
| Sesión del día y rutina | Hoy conserva una acción de envío, biblioteca y semana existentes | No se inventa plan adaptativo clínico |
| Continuidad / racha | Meta semanal optativa, días únicos y pausa planificada | No requiere visitas diarias ni valida asistencia a una sede |
| Entrenamiento libre y explicación | Importación editable, clasificación por modalidad y ayuda breve por alias | No se copiaron vídeos, ilustraciones, branding ni interfaces |
| Tiempo disponible | Estimación explícita de ritmo de registro; omisión solo de trabajo autorizado | No se garantiza hora exacta ni se reduce descanso obligatorio |

[Hevy: opciones de ejercicios](https://www.hevyapp.com/features/exercise-programming-options/) documenta reordenación y sustitución. No se presenta ninguna de esas funciones como exclusiva. La prioridad es su combinación útil con Watch, historial local y contexto portátil. No se incorporan funciones comerciales ajenas al encargo.

## Caminadora

[Apple: precisión del Watch](https://support.apple.com/en-ie/105002) diferencia actividades y condiciones de estimación. Little Lift conserva walking/running indoor; su distancia es una lectura manual opcional de la máquina. No usa GPS para medir una cinta estática, ni presenta velocidad/inclinación como sensor medido. Los intervalos entre Start/Pause/Resume/Done son eventos explícitos; los objetivos permanecen separados y los datos ausentes siguen ausentes.
