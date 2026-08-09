-- Triagem Inteligente de Mensagens — BKM Advogados
-- Schema do banco de dados (Supabase / Postgres)

create table mensagens (
  id uuid primary key default gen_random_uuid(),
  mensagem_id integer not null,
  canal text not null,
  remetente text not null,
  categoria text not null,
  nome_cliente text,
  numero_processo text,
  data_prazo date,
  resumo text,
  remetente_tipo text,
  confianca text,
  erro_processamento text,
  processado_em timestamptz default now(),
  created_at timestamptz default now(),
  unique (mensagem_id)
);

create table resumos_diarios (
  id uuid primary key default gen_random_uuid(),
  data date not null,
  total_mensagens integer,
  total_urgentes integer,
  categorias_json jsonb,
  resumo_texto text,
  created_at timestamptz default now()
);

-- Row Level Security: leitura pública (necessária para o painel),
-- escrita restrita à service_role (usada exclusivamente pelas automações do n8n)

alter table mensagens enable row level security;
alter table resumos_diarios enable row level security;

create policy "Permitir leitura pública" on mensagens
  for select using (true);

create policy "Permitir leitura pública" on resumos_diarios
  for select using (true);
