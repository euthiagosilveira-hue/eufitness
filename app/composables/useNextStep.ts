// Guarda para onde a pessoa ia (ex.: um convite) enquanto ela entra ou
// confirma o e-mail, que pode acontecer em outra aba.
const KEY = 'ef_next'

function safe(path: unknown) {
  return typeof path === 'string' && path.startsWith('/') && !path.startsWith('//') ? path : null
}

export function useNextStep() {
  function remember(path: string) {
    try { localStorage.setItem(KEY, path) } catch {}
  }

  function take() {
    try {
      const path = safe(localStorage.getItem(KEY))
      localStorage.removeItem(KEY)
      return path
    } catch {
      return null
    }
  }

  /** Depois do login: vai para o passo guardado ou para o painel do papel. */
  async function continueAfterLogin() {
    const { load } = useMe()
    const next = take()
    if (next) return navigateTo(next, { replace: true })
    const me = await load(true)
    return navigateTo(homeFor(me), { replace: true })
  }

  return { remember, take, continueAfterLogin }
}
