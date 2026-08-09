# Triagem Inteligente de Mensagens — BKM Advogados

Automação que classifica mensagens de clientes (WhatsApp/e-mail) usando LLM, extrai campos estruturados, grava em banco de dados e gera resumo diário. Inclui painel visual para consulta e análise.

**Painel:** https://testetcnico.lovable.app/
**Vídeo demonstrativo:** 🎥 [Assista aqui](https://drive.google.com/file/d/1lijyutu4Y3wra1YI-OZPCT9CI8lq2ClI/view?usp=sharing)
---

## Arquitetura

```
┌─────────────┐    ┌────────────┐    ┌──────────────┐    ┌─────────────────┐    ┌───────────────┐    ┌──────────────────┐
│   Webhook   │───▶│ Split Out  │───▶│ Extrair Campos│───▶│ Classificar com │───▶│ Validar e     │───▶│ Gravar no Supabase│
│  (receber   │    │ (separar   │    │ da Mensagem   │    │ IA (LLM Agent)  │    │ Tratar Saída  │    │   (Upsert)        │
│  mensagens) │    │ 1 por 1)   │    │               │    │ GPT-4.1-mini    │    │ da IA         │    │                   │
└─────────────┘    └────────────┘    └──────────────┘    └─────────────────┘    └───────────────┘    └──────────────────┘
     Fluxo 1: Ingestão e Classificação (disparado por evento — 1 execução por lote de mensagens)


┌──────────────┐    ┌───────────────────┐    ┌────────────────────────────┐    ┌─────────────────────┐
│  Disparo     │───▶│ Buscar Mensagens  │───▶│ Agregar por Categoria e    │───▶│ Gravar Resumo no     │
│  Diário (18h)│    │ do Dia            │    │ Montar Resumo              │    │ Supabase             │
└──────────────┘    └───────────────────┘    └────────────────────────────┘    └─────────────────────┘
     Fluxo 2: Resumo Diário (agendado, 1x por dia)


┌─────────────────────────────────────────────────────────────────┐
│  Painel (Lovable) — lê diretamente do Supabase                  │
│  KPIs · Urgentes em destaque · Categorias · Fila de revisão     │
│  manual · Histórico de resumos diários                          │
└─────────────────────────────────────────────────────────────────┘
```

**Banco de dados (Supabase/Postgres):**

- `mensagens`: uma linha por mensagem processada, com categoria, campos extraídos, confiança e flag de erro. Chave única em `mensagem_id` permite upsert (evita duplicação se a mesma mensagem for reprocessada).
- `resumos_diarios`: uma linha por dia, com totais agregados e o texto do resumo pronto para leitura/compartilhamento.

---

## Por que cada ferramenta

**n8n (orquestração)** — Editor visual facilita mostrar a arquitetura na entrevista de walkthrough, tem nodes nativos para LLM (LangChain), Supabase e webhooks, e é auto-hospedável (sem lock-in de plataforma). Alternativa considerada: código puro em Python — mais rápido de testar isoladamente, mas menos didático para apresentar visualmente.

**OpenAI GPT-4.1-mini (LLM)** — Bom equilíbrio custo/qualidade para uma tarefa de classificação + extração estruturada (não exige raciocínio complexo). Testado com prompt que exige saída em JSON puro, sem markdown, com regras explícitas de "nunca invente dados" para reduzir alucinação.

**Supabase (armazenamento)** — Postgres gerenciado com API REST pronta (PostgREST), permitindo upsert nativo via header `Prefer: resolution=merge-duplicates` — resolve deduplicação sem código extra. Alternativa a Google Sheets, que foi testado primeiro mas apresentou problemas de tipagem automática (telefone virando número, data virando datetime ambíguo).

**Lovable (painel)** — Gera interface completa a partir de um prompt em linguagem natural, conectada diretamente ao schema do Supabase existente, sem precisar escrever frontend do zero. Adicionado como diferencial além do escopo mínimo pedido no teste.

---

## Tratamento de erro e alucinação (LLM)

- Prompt define formato de saída rígido (JSON puro, sem blocos markdown) e uma lista fechada de categorias válidas.
- Node de código (`Validar e Tratar Saída da IA`) faz parse defensivo: remove crases residuais caso o modelo as inclua mesmo assim, valida a categoria contra a lista permitida (fallback seguro se vier algo fora do padrão), valida o formato do número de processo (CNJ) via regex, e converte/valida a data de prazo.
- Todo erro de parse ou validação é registrado no campo `erro_processamento` — a mensagem não é perdida nem trava o fluxo, apenas fica marcada para revisão manual (visível no painel).
- O prompt inclui uma regra específica para identificar quando o remetente é a parte contrária (não cliente), mesmo que a categoria seja `urgente_prazo` — testado com o caso do item 9 da massa de teste.

---

## Como rodar

1. Importe os dois workflows (`n8n-workflows/ingestao-classificacao.json` e `n8n-workflows/resumo-diario.json`) no n8n.
2. Configure as credenciais:
   - **OpenAI API** (chave própria)
   - **Supabase API** (Host do projeto + Service Role Key)
3. Crie as tabelas no Supabase rodando o SQL em `supabase/schema.sql`.
4. Ative os dois workflows.
5. Dispare o teste enviando um POST para a URL do Webhook com o conteúdo de `dados-teste/mensagens_entrada.json`.
6. Confira o resultado nas tabelas `mensagens` e `resumos_diarios`, ou diretamente no painel: https://testetcnico.lovable.app/

---

## Estimativa de custo mensal (produção, ~500 mensagens/dia)

Volume: ~15.000 mensagens/mês.

| Item | Estimativa | Observação |
|---|---|---|
| LLM (GPT-4.1-mini) | **≈ US$ 8/mês** | ~700 tokens de entrada + ~150 de saída por mensagem × 15.000 msgs (preço oficial OpenAI: US$0,40/1M entrada, US$1,60/1M saída) |
| Supabase | **US$ 0 a US$ 25/mês** | Free tier cobre o volume de dados tranquilamente; plano Pro (US$25) recomendado em produção por causa de backups automáticos e sem pausa por inatividade |
| Hospedagem n8n | **US$ 6 a US$ 24/mês** | VPS pequena self-hosted (~US$6-12) ou n8n Cloud Starter (~US$20-24), dependendo da preferência por manutenção própria vs. gerenciado |
| Lovable (painel) | **US$ 0/mês** | Free tier suficiente para um painel interno de consulta; Pro (~US$25) só se precisar de mais alterações/mês ou domínio próprio |
| **Total estimado** | **≈ US$ 15 a US$ 55/mês** | Maior parte do custo é infraestrutura, não o LLM |

*Estimativa sujeita a variação conforme tamanho médio real das mensagens e picos de volume.*

---

## O que faria diferente com mais tempo

- **Autenticação no painel** (Lovable já suporta, não configurada por estar fora do escopo mínimo do teste).
- **Retry automático** no node de LLM para chamadas que falharem por instabilidade da API (hoje não há retry configurado).
- **Fila com rate limiting** (`Split In Batches`) para não estourar limite de requisições por minuto da API do LLM em picos de volume.
- **Alertas ativos** (WhatsApp/e-mail/Slack) disparando automaticamente quando uma mensagem `urgente_prazo` é classificada, em vez de depender só da consulta manual do resumo diário.
- **Testes automatizados** do prompt (eval set maior que as 10 mensagens fornecidas) para medir taxa de acerto de categoria de forma mais robusta antes de ir para produção.
- **Detecção de cliente já existente**, cruzando `de` (telefone/e-mail) com uma lista de clientes cadastrados, para enriquecer `nome_cliente` automaticamente quando o remetente já for conhecido.

---

## Estrutura do repositório

```
├── README.md
├── n8n-workflows/
│   ├── ingestao-classificacao.json
│   └── resumo-diario.json
├── supabase/
│   └── schema.sql
├── dados-teste/
│   └── mensagens_entrada.json
└── resultado/
    ├── mensagens_rows.csv
    └── resumos_diarios_rows.csv
```
