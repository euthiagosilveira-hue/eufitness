-- Eu Fitness · Fase 1: assessorias (tenants), perfis, vínculos e convites.
-- Cole este arquivo inteiro no SQL Editor do Supabase e rode uma vez.

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------
create type public.member_role as enum ('personal', 'nutri', 'aluno');
create type public.link_status as enum ('ativo', 'pausado', 'encerrado');

-- ---------------------------------------------------------------------------
-- Tabelas
-- ---------------------------------------------------------------------------

-- Um login, um perfil. Criado automaticamente no cadastro (trigger abaixo).
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  phone text,
  timezone text not null default 'America/Sao_Paulo',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Assessoria = o cliente do SaaS. Cada personal que assina tem a sua.
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 80),
  owner_id uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

-- Quem participa de cada assessoria e com qual papel.
-- registry guarda o CREF (personal) ou CRN (nutri).
create table public.memberships (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role public.member_role not null,
  is_admin boolean not null default false,
  registry text,
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);
create index memberships_user_idx on public.memberships (user_id);

-- Vínculo profissional → aluno. É o que as permissões dos planos vão usar.
create table public.coach_students (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  professional_id uuid not null references public.profiles (id) on delete cascade,
  student_id uuid not null references public.profiles (id) on delete cascade,
  status public.link_status not null default 'ativo',
  since date not null default current_date,
  primary key (professional_id, student_id),
  check (professional_id <> student_id)
);
create index coach_students_student_idx on public.coach_students (student_id);
create index coach_students_org_idx on public.coach_students (organization_id);

-- Convite por link. Quem aceita entra na assessoria com o papel do convite;
-- se for aluno, também fica vinculado a quem convidou.
create table public.invites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  invited_by uuid not null references public.profiles (id) on delete cascade,
  role public.member_role not null,
  name text,
  code text not null unique default replace(gen_random_uuid()::text, '-', ''),
  expires_at timestamptz not null default now() + interval '7 days',
  accepted_by uuid references public.profiles (id),
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);
create index invites_org_idx on public.invites (organization_id);

-- ---------------------------------------------------------------------------
-- Funções auxiliares (security definer evita recursão nas políticas)
-- ---------------------------------------------------------------------------
create or replace function public.is_member(org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships m
    where m.organization_id = org and m.user_id = (select auth.uid())
  );
$$;

create or replace function public.is_admin(org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships m
    where m.organization_id = org and m.user_id = (select auth.uid()) and m.is_admin
  );
$$;

create or replace function public.is_professional(org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships m
    where m.organization_id = org and m.user_id = (select auth.uid())
      and m.role in ('personal', 'nutri')
  );
$$;

-- Dois usuários se enxergam se forem da mesma assessoria e pelo menos um
-- deles for profissional (alunos não veem outros alunos).
create or replace function public.can_see_profile(target uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select target = (select auth.uid()) or exists (
    select 1
    from public.memberships me
    join public.memberships other on other.organization_id = me.organization_id
    where me.user_id = (select auth.uid()) and other.user_id = target
      and (me.role <> 'aluno' or other.role <> 'aluno')
  );
$$;

-- ---------------------------------------------------------------------------
-- Cadastro: cria o perfil quando o usuário se registra
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Ações (RPC). O app chama estas funções em vez de inserir direto.
-- ---------------------------------------------------------------------------

-- Personal cria a própria assessoria e vira administrador dela.
create or replace function public.create_organization(org_name text, cref text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  org_id uuid;
begin
  if uid is null then
    raise exception 'Faça login para continuar';
  end if;
  if exists (select 1 from public.memberships where user_id = uid and role = 'personal' and is_admin) then
    raise exception 'Você já tem uma assessoria';
  end if;

  insert into public.organizations (name, owner_id) values (trim(org_name), uid)
  returning id into org_id;

  insert into public.memberships (organization_id, user_id, role, is_admin, registry)
  values (org_id, uid, 'personal', true, nullif(trim(cref), ''));

  return org_id;
end;
$$;

-- Mostra o convite para quem abre o link (ainda sem login).
create or replace function public.get_invite(invite_code text)
returns table (organization_name text, role public.member_role, invited_by_name text, name text, valid boolean)
language sql stable security definer set search_path = '' as $$
  select o.name, i.role, p.full_name, i.name,
         i.accepted_at is null and i.expires_at > now()
  from public.invites i
  join public.organizations o on o.id = i.organization_id
  join public.profiles p on p.id = i.invited_by
  where i.code = invite_code;
$$;

-- Aceita o convite: entra na assessoria e, se for aluno, cria o vínculo.
create or replace function public.accept_invite(invite_code text, registry text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  inv public.invites%rowtype;
begin
  if uid is null then
    raise exception 'Faça login para continuar';
  end if;

  select * into inv from public.invites where code = invite_code for update;
  if not found then
    raise exception 'Convite não encontrado';
  end if;
  if inv.accepted_at is not null then
    raise exception 'Este convite já foi usado';
  end if;
  if inv.expires_at <= now() then
    raise exception 'Este convite expirou. Peça um novo';
  end if;
  if inv.invited_by = uid then
    raise exception 'Você não pode aceitar o próprio convite';
  end if;

  insert into public.memberships (organization_id, user_id, role, registry)
  values (inv.organization_id, uid, inv.role, nullif(trim(registry), ''))
  on conflict (organization_id, user_id) do nothing;

  if inv.role = 'aluno' then
    insert into public.coach_students (organization_id, professional_id, student_id)
    values (inv.organization_id, inv.invited_by, uid)
    on conflict do nothing;
  end if;

  update public.invites set accepted_by = uid, accepted_at = now() where id = inv.id;
  return inv.organization_id;
end;
$$;

-- Vincula um aluno da assessoria a um profissional (ex.: o nutri parceiro).
create or replace function public.link_student(org uuid, professional uuid, student uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin(org) then
    raise exception 'Só o administrador da assessoria pode vincular alunos';
  end if;
  if not exists (select 1 from public.memberships where organization_id = org and user_id = professional and role in ('personal', 'nutri')) then
    raise exception 'Profissional não pertence à assessoria';
  end if;
  if not exists (select 1 from public.memberships where organization_id = org and user_id = student and role = 'aluno') then
    raise exception 'Aluno não pertence à assessoria';
  end if;

  insert into public.coach_students (organization_id, professional_id, student_id)
  values (org, professional, student)
  on conflict (professional_id, student_id) do update set status = 'ativo';
end;
$$;

revoke execute on function public.create_organization(text, text) from public, anon;
revoke execute on function public.accept_invite(text, text) from public, anon;
revoke execute on function public.link_student(uuid, uuid, uuid) from public, anon;
grant execute on function public.create_organization(text, text) to authenticated;
grant execute on function public.accept_invite(text, text) to authenticated;
grant execute on function public.link_student(uuid, uuid, uuid) to authenticated;
grant execute on function public.get_invite(text) to anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Segurança por linha (RLS)
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.organizations enable row level security;
alter table public.memberships enable row level security;
alter table public.coach_students enable row level security;
alter table public.invites enable row level security;

-- profiles
create policy "ver perfis da mesma assessoria" on public.profiles
  for select to authenticated using (public.can_see_profile(id));
create policy "editar o próprio perfil" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- organizations
create policy "membros veem a assessoria" on public.organizations
  for select to authenticated using (public.is_member(id));
create policy "admin edita a assessoria" on public.organizations
  for update to authenticated using (public.is_admin(id)) with check (public.is_admin(id));

-- Colunas que o app pode alterar direto. Papel, administrador e vínculos
-- só mudam pelas funções acima, para ninguém se promover sozinho.
revoke update on public.memberships, public.organizations, public.coach_students, public.profiles from authenticated, anon;
grant update (name) on public.organizations to authenticated;
grant update (status) on public.coach_students to authenticated;
grant update (full_name, phone, timezone) on public.profiles to authenticated;

-- memberships: alunos só veem a própria linha e as dos profissionais
create policy "ver membros" on public.memberships
  for select to authenticated using (
    user_id = (select auth.uid())
    or public.is_professional(organization_id)
    or (public.is_member(organization_id) and role <> 'aluno')
  );
create policy "admin remove membros" on public.memberships
  for delete to authenticated using (public.is_admin(organization_id) and user_id <> (select auth.uid()));

-- coach_students
create policy "ver vínculos" on public.coach_students
  for select to authenticated using (
    professional_id = (select auth.uid())
    or student_id = (select auth.uid())
    or public.is_admin(organization_id)
  );
create policy "profissional ou admin muda o status" on public.coach_students
  for update to authenticated
  using (professional_id = (select auth.uid()) or public.is_admin(organization_id))
  with check (professional_id = (select auth.uid()) or public.is_admin(organization_id));

-- invites: profissionais convidam alunos; só o admin convida profissionais
create policy "profissionais veem convites da assessoria" on public.invites
  for select to authenticated using (public.is_professional(organization_id));
create policy "criar convites" on public.invites
  for insert to authenticated with check (
    invited_by = (select auth.uid())
    and public.is_professional(organization_id)
    and (role = 'aluno' or public.is_admin(organization_id))
  );
create policy "apagar convites próprios" on public.invites
  for delete to authenticated using (
    accepted_at is null
    and (invited_by = (select auth.uid()) or public.is_admin(organization_id))
  );
