export const PROD_HOST = "luma-admin.chrl.cloud";

/** Anything but the prod hostname (dev domain, localhost) shows the DEV badge. */
export const isDevHost = (hostname: string) => hostname !== PROD_HOST;
