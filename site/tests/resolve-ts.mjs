// The source imports without a file extension, which Vite resolves and node does not. This adds the
// same step for `node --test`: a relative import with no extension is tried as .ts, then as written.
export async function resolve(specifier, context, next) {
  if (specifier.startsWith('.') && !/\.[a-z]+$/i.test(specifier)) {
    try {
      return await next(`${specifier}.ts`, context)
    } catch {
      // fall through to node's own resolution, which reports the original specifier
    }
  }
  return next(specifier, context)
}
