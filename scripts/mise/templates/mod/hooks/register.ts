import type { Register } from 'claude-code'

export const register: Register = (on) => {
  on('tool.call', async ($, e, next) => next(e))
}
