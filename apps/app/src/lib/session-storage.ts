import AsyncStorage from '@react-native-async-storage/async-storage';
import { AESEncryptionKey, AESSealedData, aesDecryptAsync, aesEncryptAsync } from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';

// Where Supabase keeps the signed-in session on iOS and Android.
//
// The session is a JWT plus refresh token -- whoever has it is the user, with
// access to every memory they can see. The OS keychain (SecureStore) is the
// right place for it but caps values at about 2KB, which a session exceeds.
// So each value is sealed with AES-256-GCM: the ciphertext goes in
// AsyncStorage and a fresh key per write goes in SecureStore. Reading either
// one alone gives nothing.

// Decodes base64 to a UTF-8 string without TextDecoder, which Hermes lacks
// on some versions. Names in the session can be non-ASCII.
function fromBase64Utf8(base64: string): string {
  const binary = atob(base64);
  let escaped = '';
  for (let i = 0; i < binary.length; i++) {
    escaped += '%' + binary.charCodeAt(i).toString(16).padStart(2, '0');
  }
  return decodeURIComponent(escaped);
}

export const sessionStorage = {
  async getItem(name: string): Promise<string | null> {
    const [sealed, keyHex] = await Promise.all([
      AsyncStorage.getItem(name),
      SecureStore.getItemAsync(name),
    ]);
    if (!sealed || !keyHex) return null;
    try {
      const key = await AESEncryptionKey.import(keyHex, 'hex');
      const plain = await aesDecryptAsync(AESSealedData.fromCombined(sealed), key, {
        output: 'base64',
      });
      return fromBase64Utf8(plain);
    } catch {
      // Tampered with, or one half lost (e.g. restored from a backup without
      // the keychain). Treat as signed out.
      return null;
    }
  },

  async setItem(name: string, value: string): Promise<void> {
    const key = await AESEncryptionKey.generate();
    const sealed = await aesEncryptAsync(new TextEncoder().encode(value), key);
    await SecureStore.setItemAsync(name, await key.encoded('hex'));
    await AsyncStorage.setItem(name, await sealed.combined('base64'));
  },

  async removeItem(name: string): Promise<void> {
    await Promise.all([AsyncStorage.removeItem(name), SecureStore.deleteItemAsync(name)]);
  },
};
