/** Money never passes through Number, parseFloat, or binary floating-point arithmetic. */
export function canonicalMoney(input: string): string {
  const value = input.trim();
  if (!/^\d{1,16}(?:\.\d{1,2})?$/.test(value)) throw new Error('Masukkan jumlah positif, maksimal 16 digit dan 2 desimal. Gunakan titik untuk desimal.');
  const separator = value.indexOf('.');
  const whole = separator < 0 ? value : value.slice(0, separator);
  const fraction = separator < 0 ? '' : value.slice(separator + 1);
  const cents = BigInt(whole) * 100n + BigInt(fraction.padEnd(2, '0'));
  if (cents <= 0n) throw new Error('Jumlah harus lebih besar dari nol.');
  return `${cents / 100n}.${(cents % 100n).toString().padStart(2, '0')}`;
}
export function formatMoney(input: string): string {
  if (!/^-?\d+(?:\.\d{1,2})?$/.test(input)) throw new Error('Jumlah dari server tidak valid.');
  const negative = input.startsWith('-');
  const unsigned = input.replace(/^-/, '');
  const separator = unsigned.indexOf('.');
  const whole = separator < 0 ? unsigned : unsigned.slice(0, separator);
  const fraction = separator < 0 ? '00' : unsigned.slice(separator + 1);
  return `${negative ? '−' : ''}Rp ${whole.replace(/\B(?=(\d{3})+(?!\d))/g, '.')},${fraction.padEnd(2, '0')}`;
}
export function todayJakarta(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
}
