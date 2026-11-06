const json = (statusCode, body) => ({
  statusCode,
  headers: {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  },
  body: JSON.stringify(body)
});

const MAX_HISTORY = 10;
const MAX_MESSAGE_LENGTH = 4000;

function cleanHistory(history) {
  if (!Array.isArray(history)) return [];
  return history.slice(-MAX_HISTORY).map((item) => ({
    role: item?.role === "assistant" ? "assistant" : "user",
    content: String(item?.content || "").slice(0, 1500)
  })).filter((item) => item.content.trim());
}

function cleanProducts(context) {
  if (!context || !Array.isArray(context.products)) return [];
  return context.products.slice(0, 60).map((p) => ({
    name: String(p?.name || "").slice(0, 100),
    description: String(p?.description || "").slice(0, 350),
    category: String(p?.category || "").slice(0, 80),
    price: p?.price ?? null,
    minimum: p?.minimum ?? 1,
    seller: String(p?.seller || "").slice(0, 80),
    stock: p?.stock ?? null
  }));
}

export const handler = async (event) => {
  if (event.httpMethod !== "POST") {
    return json(405, { error: "Méthode non autorisée. Utilisez POST." });
  }

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return json(503, { error: "Le service IA n'est pas configuré sur le serveur." });
  }

  let payload;
  try {
    payload = JSON.parse(event.body || "{}");
  } catch {
    return json(400, { error: "Corps JSON invalide." });
  }

  const message = String(payload.message || "").trim();
  if (!message) return json(400, { error: "Le message est vide." });
  if (message.length > MAX_MESSAGE_LENGTH) {
    return json(413, { error: "Le message est trop long." });
  }

  const language = payload.language === "mg" ? "mg" : "fr";
  const products = cleanProducts(payload.context);

  const systemInstruction = language === "mg"
    ? `Ianao no mpanampy ofisialin'ny MadaGrossiste, tsena ambongadiny eto Madagasikara. Valio amin'ny teny Malagasy mazava sy tsotra. Ampio ny mpividy hahita vokatra sy ny mpivarotra hitantana ny fivarotany. Mampiasà ny lisitry ny vokatra nomena ihany. Aza mamorona vokatra, vidiny, tahiry, mpivarotra, baiko na satan'ny fandoavam-bola. Raha tsy hita ny vaovao dia lazao mazava fa tsy voamarina ary asao izy hifandray amin'ny mpivarotra. Tsy afaka mametraka baiko na manamarina fandoavam-bola ianao.`
    : `Tu es l'assistant officiel de MadaGrossiste, une marketplace de vente en gros à Madagascar. Réponds en français clair et simple. Aide les acheteurs à trouver des produits et les vendeurs à gérer leur boutique. Utilise uniquement les produits fournis dans le contexte. N'invente jamais de produits, prix, stocks, vendeurs, commandes ou statuts de paiement. Si une information manque, indique qu'elle n'est pas vérifiée et conseille de contacter le vendeur. Tu ne peux ni passer une commande ni confirmer un paiement.`;

  const productContext = products.length
    ? `\n\nCatalogue disponible (données fournies par l'application) :\n${JSON.stringify(products)}`
    : "\n\nAucun produit du catalogue n'a été transmis pour cette question. Ne prétends pas avoir vérifié le catalogue.";

  const messages = [
    { role: "system", content: systemInstruction + productContext },
    ...cleanHistory(payload.history),
    { role: "user", content: message }
  ];

  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";
  const endpoint = "https://api.openai.com/v1/chat/completions";

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`
      },
      body: JSON.stringify({
        model,
        messages,
        max_completion_tokens: 900,
        temperature: 0.35
      })
    });

    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      console.error("OpenAI API error:", response.status, result?.error?.message || "Unknown error");
      return json(502, {
        error: "Le service IA est momentanément indisponible. Réessayez plus tard."
      });
    }

    const reply = result?.choices?.[0]?.message?.content?.trim();

    if (!reply) {
      return json(502, { error: "L'IA n'a pas renvoyé de réponse exploitable." });
    }

    return json(200, { reply, provider: "OpenAI", model });
  } catch (error) {
    console.error("Chat function error:", error?.message || error);
    return json(502, { error: "Impossible de joindre le service IA pour le moment." });
  }
};
