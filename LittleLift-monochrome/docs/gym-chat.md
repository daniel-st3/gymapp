# Tu entrenamiento del chat al Watch

En **Entrenar**, toca **Pegar** después de copiar el entrenamiento de tu chat, o **Captura** para elegir una imagen. La app abre la revisión directamente. Comprueba los ejercicios y toca **Usar este entrenamiento**. Se envía al Watch; abre Little Lift allí y toca **Iniciar**.

No necesitas JSON. Este ejemplo ficticio muestra el formato sencillo que ahora pide la app:

```text
Workout: Pierna de ejemplo
Prensa de piernas — 2 x 10 — 20 kg — descanso 60 s
Curl femoral sentado — 1 x 12 — 15 kg — descanso 60 s
```

Los bloques de texto de ChatGPT también se aceptan, incluso con una introducción o despedida alrededor. Una carga ausente puede escribirse directamente en la revisión o elegirse en el Watch. Si faltan unidad o descanso, se confirman en la revisión; los rangos necesitan un objetivo elegido. No se inventan datos ni se guarda nada antes de aceptar. Un título como «pierna» por sí solo no contiene una rutina.

Si falta algo, **Por completar** muestra el ejercicio y el dato pendiente. Toca ese elemento o **Revisar lo que falta** para llegar al campo. Al completarlo, el botón cambia a **Usar este entrenamiento**. `lb`, `lbs` y `libras` se conservan; si una captura confunde la unidad, confirma kg o lb una vez sin volver a escribir los números.

No tienes que escribir la fecha. El mensaje que copias incluye la fecha local de hoy y pide todas las cargas y unidades ya acordadas. El registro del entrenamiento usa la fecha real al iniciar en el Watch. Si ChatGPT omite un peso que conoces, puedes añadirlo en la revisión; la app no puede recuperarlo de un chat que no lee.

## Mantener tu conversación al día

**Ajustes → Mi chat del gym → Copiar mensaje actualizado** prepara el contexto permitido: plan guardado, resultados reales, preferencias autorizadas y una solicitud de respuesta sencilla. Puedes añadir «hoy acordamos pierna». Abre tu conversación habitual y pega el mensaje. Después trae la respuesta con Pegar.

El botón **Abrir ChatGPT** usa el enlace oficial para la app, sin abrir automáticamente el navegador si iOS lo rechaza. Para dirigirte a un chat concreto puedes guardar su dirección privada en **… → Enlace a mi conversación**. Es opcional y se guarda solo en ese iPhone. Debe ser `https://chatgpt.com/c/...`, copiada de la barra de direcciones; no uses Compartir ni publiques el chat. Sin ese enlace, tú eliges la conversación dentro de ChatGPT. La app no puede adivinar cuál utilizas ni comprobar qué conversación quedó visible.

Después del entrenamiento, cuando aparezca en Historial, copia otro mensaje actualizado para llevar los resultados al mismo chat. El contexto incluye hasta ocho registros recientes de cada origen y se identifica como parcial. Un plan guardado es una prescripción, no evidencia de trabajo realizado.

**… → Elegir qué incluir** controla perfil, historial y equipo. Little Lift no lee la conversación ni confirma que hayas enviado el texto. No hay sincronización automática con ChatGPT.

## Recuperación y compatibilidad

El JSON anterior sigue admitido. Los datos básicos incompletos se abren como borrador editable. Las observaciones avanzadas, IDs y respuestas de Atajos mantienen su validación; no se descartan para forzar una importación.

Una respuesta JSON vinculada a una solicitud antigua no sustituye el plan automáticamente. Puedes revisarla explícitamente como un entrenamiento independiente; ya no se presentará como respuesta a la solicitud actual. Si el texto está mal formado, se conserva para corregirlo y se ofrece un mensaje breve para pedir otro formato.

La revisión mediante Atajos es una vía separada: no hereda ni selecciona tu conversación anterior.

## Fuentes de la apertura de ChatGPT

La configuración oficial de [enlaces de la app de ChatGPT](https://chatgpt.com/.well-known/apple-app-site-association) incluye `/open-app` y `/c/*` (consultada el 20 de octubre de 2026). Little Lift usa la opción de Apple [universalLinksOnly](https://developer.apple.com/documentation/uikit/uiapplication/openexternalurloptionskey/universallinksonly) para impedir una apertura silenciosa del navegador. Los [enlaces compartidos](https://help.openai.com/en/articles/7925741-sharing-conversations-and-scheduled-tasks-in-chatgpt) no son el enlace privado de una conversación.
