# Usar el chat del gimnasio que ya tienes

Para traer una rutina que tu chat ya te dio, entra en **Entrenar → Traer entrenamiento del chat** y elige **Usar una captura** o **Pegar**. Si no se puede leer completa, **Copiar mensaje para mi chat**, que aparece junto a la explicación del problema, pide un formato sencillo, sin cambiar lo acordado.

Para compartir contexto e historial, en **Ajustes → Mi chat del gym**, toca **Copiar mensaje actualizado**. Puedes escribir antes
algo breve como «hoy acordamos pierna y tengo 45 minutos». Abre tu conversación habitual
con ChatGPT y pega el mensaje. Incluye los datos que permitiste compartir y pide una
respuesta que Little Lift pueda importar. No necesitas redactar JSON tú.

Copia el bloque completo que devuelva tu chat. Vuelve a **Mi chat del gym → Pegar**.
Comprueba o edita los ejercicios y toca **Usar entrenamiento y enviar al Watch**.
Hasta ese momento el plan guardado sigue igual. Desde Añadir rutina, el mismo editor
guarda para otro día y conserva Hoy.

Después de entrenar, espera a que el registro aparezca en Historial. Mi chat del gym
mostrará que hay datos nuevos. Copia otro mensaje para llevar los resultados reales a
esa conversación. El export incluye hasta ocho registros recientes de cada origen y
explica que es parcial: el chat no debe eliminar registros antiguos ausentes.

**Elegir qué incluir** permite revisar perfil, historial y equipo antes de copiar.
Los cambios se guardan al pulsar **Vista previa del contexto**. El plan actual siempre
se identifica como prescripción; no equivale a haber realizado el entrenamiento.

## Formato de referencia

Este ejemplo es ficticio, no una recomendación. El identificador debe ser exactamente
el generado por la app para tu último mensaje; el de este ejemplo no sirve como recibo.

```json
{
  "handoffID": "11111111-1111-4111-8111-111111111111",
  "analysis": "Hoy acordamos pierna; el plan guardado de torso se revisa antes de cambiarlo.",
  "plan": {
    "schemaVersion": 3,
    "title": "Pierna de ejemplo",
    "unit": "kg",
    "exercises": [
      {"name": "Prensa de piernas", "sets": 2, "reps": 10, "weight": 20, "restSeconds": 60}
    ]
  }
}
```

Una respuesta usada, de otro mensaje o basada en datos que cambiaron no reemplaza Hoy.
Copia un mensaje actualizado y pide a tu chat que responda a ese mensaje. Los formatos
anteriores de texto, imagen y JSON siguen disponibles con revisión explícita.

## Qué significa «mantener al día»

La app prepara contexto y recibe el resultado que tú traes. No entra en tu conversación,
no confirma que hayas pegado un mensaje y no envía sesiones automáticamente. Abrir
ChatGPT abre su destino oficial; debes elegir tu chat. El atajo opcional de análisis
sigue siendo otra vía y no hereda ni selecciona una conversación anterior.

Las fuentes oficiales consultadas explican que los enlaces personales compartidos
son instantáneas y responder a ellos crea otra conversación, no un canal de sync:
[conversaciones compartidas](https://help.openai.com/en/articles/7925741-sharing-conversations-and-scheduled-tasks-in-chatgpt).
La [extensión de ChatGPT para Apple Intelligence](https://help.openai.com/en/articles/10269382-setting-up-chatgpt-with-apple-intelligence)
no documenta seleccionar este hilo existente. Little Lift no introduce una API privada
para suplir esa limitación.
