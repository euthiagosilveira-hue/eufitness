import type { MemberRole } from '~/types/database.types'

declare module '#app' {
  interface PageMeta {
    /** Papéis que podem abrir a página. */
    roles?: MemberRole[]
  }
}

// Garante que só o papel certo abre cada painel; quem cai no lugar errado
// volta para o próprio painel.
export default defineNuxtRouteMiddleware(async (to) => {
  const roles = to.meta.roles
  if (!roles?.length) return

  const { load } = useMe()
  const me = await load()
  if (!me) return navigateTo('/login')

  const role = me.current?.role
  if (!role || !roles.includes(role)) return navigateTo(homeFor(me))
})
