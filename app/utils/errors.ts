// Traduz as mensagens mais comuns do Supabase Auth para o português.
const known: [RegExp, string][] = [
  [/invalid login credentials/i, 'E-mail ou senha incorretos.'],
  [/email not confirmed/i, 'Confirme seu e-mail pelo link que enviamos antes de entrar.'],
  [/user already registered/i, 'Já existe uma conta com este e-mail. Tente entrar.'],
  [/password should be at least/i, 'A senha precisa ter pelo menos 6 caracteres.'],
  [/rate limit|too many/i, 'Muitas tentativas. Espere um pouco e tente de novo.'],
  [/unable to validate email|invalid email/i, 'Este e-mail não parece válido.'],
]

export function friendlyError(error: unknown) {
  const message = error instanceof Error ? error.message : typeof error === 'object' && error && 'message' in error ? String(error.message) : String(error)
  for (const [pattern, text] of known) if (pattern.test(message)) return text
  return message || 'Algo deu errado. Tente de novo.'
}
