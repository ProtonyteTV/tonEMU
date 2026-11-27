package com.jedplatforms.jedEmu;

import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

/**
 * Writes player Nickname and Birthday into the native system/NAND files read by
 * melonDS (NDS) and Azahar/Citra (3DS) before GLRetroView initializes the core.
 */
final class SystemProfileWriter {
    private SystemProfileWriter() {}

    static void apply(String coreName, File systemDir, File savesDir,
                      String rawNickname, int rawMonth, int rawDay) {
        apply(coreName, systemDir, savesDir, rawNickname, rawMonth, rawDay, -1);
    }

    /**
     * [favoriteColor]: the DS "favorite color" (0..15, the tint of the DS menu and PictoChat), or -1
     * to leave it as it is. Ignored for the 3DS.
     */
    static void apply(String coreName, File systemDir, File savesDir,
                      String rawNickname, int rawMonth, int rawDay, int favoriteColor) {
        if (coreName == null) return;
        final int color = favoriteColor < 0 ? -1 : Math.min(15, favoriteColor);

        String nickname = sanitizeNickname(rawNickname);
        int month = Math.max(1, Math.min(12, rawMonth));
        // No impossible dates (Feb 31, Apr 31) in the DS / 3DS config.
        final int[] daysInMonth = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        int day = Math.max(1, Math.min(daysInMonth[month - 1], rawDay));

        if (CoreOptions.isMelonDs(coreName)) {
            writeNdsProfile(systemDir, savesDir, nickname, month, day, color);
        } else if (CoreOptions.is3ds(coreName)) {
            write3dsProfile(savesDir, nickname, month, day);
        }
    }

    private static String sanitizeNickname(String raw) {
        if (raw == null) return "tonEMU";
        String trimmed = raw.trim();
        if (trimmed.isEmpty()) return "tonEMU";
        if (trimmed.length() <= 10) return trimmed;
        int end = 10;
        if (Character.isHighSurrogate(trimmed.charAt(end - 1))) end--; // keep emoji whole
        return trimmed.substring(0, end);
    }

    // ───────────────────────── Nintendo DS (melonDS) ─────────────────────────

    /**
     * Builds a valid 256-byte DS User Settings block (NVRAM / wfcsettings.bin format)
     * with a valid DS firmware CRC16 checksum at 0x72.
     */
    private static void writeNdsProfile(File systemDir, File savesDir,
                                        String nickname, int month, int day, int color) {
        // melonDS checks system/wfcsettings.bin (and saves/wfcsettings.bin in some builds)
        File[] targets = new File[] {
            new File(systemDir, "wfcsettings.bin"),
            new File(savesDir, "wfcsettings.bin")
        };

        for (File target : targets) {
            try {
                byte[] buf = target.exists() ? FileUtil.readAll(target) : new byte[256];
                if (buf.length < 256) {
                    byte[] resized = new byte[256];
                    System.arraycopy(buf, 0, resized, 0, buf.length);
                    buf = resized;
                }
                // Already correct: don't bump the update counter / rewrite the file on every launch.
                if (target.exists() && userBlockMatches(buf, 0, nickname, month, day, color)) continue;
                patchDsUserBlock(buf, 0, nickname, month, day, color, !target.exists());
                GameSession.writeAtomically(target, buf);
            } catch (IOException ignored) { }
        }

        // Also patch user slots 0 and 1 inside firmware.bin if the user supplied a DS firmware dump
        File firmware = new File(systemDir, "firmware.bin");
        if (firmware.exists() && firmware.length() >= 0x40000) {
            try {
                byte[] fw = FileUtil.readAll(firmware);
                int userSettingsOffset = ((fw[0x20] & 0xFF) | ((fw[0x21] & 0xFF) << 8)) * 8;
                if (userSettingsOffset > 0 && userSettingsOffset + 0x200 <= fw.length
                    && !(userBlockMatches(fw, userSettingsOffset, nickname, month, day, color)
                         && userBlockMatches(fw, userSettingsOffset + 0x100, nickname, month, day, color))) {
                    // A real firmware dump keeps its own language (0 = Japanese is valid).
                    patchDsUserBlock(fw, userSettingsOffset, nickname, month, day, color, false);
                    patchDsUserBlock(fw, userSettingsOffset + 0x100, nickname, month, day, color, false);
                    GameSession.writeAtomically(firmware, fw);
                }
            } catch (IOException ignored) { }
        }
    }

    /** True when this user block already holds exactly this profile and has a valid checksum. */
    private static boolean userBlockMatches(byte[] buf, int base, String nickname, int month, int day, int color) {
        if (base < 0 || base + 0x74 > buf.length) return false;
        if (buf[base] != 5 || buf[base + 1] != 0) return false;
        if (buf[base + 0x03] != (byte) month || buf[base + 0x04] != (byte) day) return false;
        if (color >= 0 && (buf[base + 0x02] & 0x0F) != color) return false;

        byte[] utf16 = nickname.getBytes(StandardCharsets.UTF_16LE);
        int copyLen = Math.min(20, utf16.length);
        for (int i = 0; i < 20; i++) {
            byte want = i < copyLen ? utf16[i] : 0;
            if (buf[base + 0x06 + i] != want) return false;
        }
        int charCount = (buf[base + 0x1A] & 0xFF) | ((buf[base + 0x1B] & 0xFF) << 8);
        if (charCount != copyLen / 2) return false;

        int crc = crc16Ds(buf, base, 0x70);
        int stored = (buf[base + 0x72] & 0xFF) | ((buf[base + 0x73] & 0xFF) << 8);
        return crc == stored;
    }

    private static void patchDsUserBlock(byte[] buf, int base, String nickname, int month, int day,
                                         int color, boolean defaultEnglish) {
        // Version = 5 (standard DS / DS Lite user settings version)
        buf[base] = 5;
        buf[base + 1] = 0;

        // Favorite color: offset 0x02 (0..15), only when the user picked one
        if (color >= 0) buf[base + 0x02] = (byte) color;

        // Birthday: offset 0x03 = month (1..12), offset 0x04 = day (1..31)
        buf[base + 0x03] = (byte) month;
        buf[base + 0x04] = (byte) day;

        // Nickname: UTF-16LE at 0x06..0x19 (20 bytes = 10 chars), char length at 0x1A..0x1B
        for (int i = 0; i < 20; i++) buf[base + 0x06 + i] = 0;
        byte[] utf16 = nickname.getBytes(StandardCharsets.UTF_16LE);
        int copyLen = Math.min(20, utf16.length);
        System.arraycopy(utf16, 0, buf, base + 0x06, copyLen);
        int charCount = copyLen / 2;
        buf[base + 0x1A] = (byte) (charCount & 0xFF);
        buf[base + 0x1B] = (byte) ((charCount >> 8) & 0xFF);

        // Ensure English language flag (bit 0..2 = 1) if unset
        if (defaultEnglish && (buf[base + 0x64] & 0x07) == 0) {
            buf[base + 0x64] = (byte) ((buf[base + 0x64] & ~0x07) | 1);
        }

        // Update count (0x70) and DS CRC16 over 0x00..0x6F stored at 0x72..0x73
        int count = (buf[base + 0x70] & 0xFF) | ((buf[base + 0x71] & 0xFF) << 8);
        count = (count + 1) & 0xFFFF;
        buf[base + 0x70] = (byte) (count & 0xFF);
        buf[base + 0x71] = (byte) ((count >> 8) & 0xFF);

        int crc = crc16Ds(buf, base, 0x70);
        buf[base + 0x72] = (byte) (crc & 0xFF);
        buf[base + 0x73] = (byte) ((crc >> 8) & 0xFF);
    }

    private static int crc16Ds(byte[] data, int offset, int length) {
        int crc = 0xFFFF;
        for (int i = 0; i < length; i++) {
            crc ^= (data[offset + i] & 0xFF);
            for (int bit = 0; bit < 8; bit++) {
                if ((crc & 1) != 0) {
                    crc = (crc >>> 1) ^ 0xA001;
                } else {
                    crc >>>= 1;
                }
            }
        }
        return crc & 0xFFFF;
    }

    // ─────────────────────── Nintendo 3DS (Azahar / Citra) ───────────────────────

    private static final int BLOCK_USERNAME = 0x000A0000;
    private static final int BLOCK_BIRTHDAY = 0x000A0001;
    private static final int ENTRY_TABLE = 0x04; // block entries follow the 4-byte config header

    /**
     * Patches or initializes the 3DS Config Savegame (`sysdata/00010017/00000000/config`)
     * inside both Azahar and Citra NAND directories under savesDir.
     */
    private static void write3dsProfile(File savesDir, String nickname, int month, int day) {
        String[] folders = new String[] { "Azahar", "Citra" };
        for (String folder : folders) {
            File configFile = new File(
                savesDir,
                folder + "/nand/data/00000000000000000000000000000000/sysdata/00010017/00000000/config"
            );
            try {
                // Never invent the file: if it is missing the core builds a complete default
                // config (language, country, sound...) on first boot, and a hand-made one would
                // stop it from doing that. The profile is applied from the next launch on.
                if (!configFile.exists()) continue;
                byte[] cfg = FileUtil.readAll(configFile);
                final byte[] original = cfg.clone();

                cfg = upsert3dsBlock(cfg, BLOCK_USERNAME, encode3dsUsername(nickname), (short) 0x000E);
                cfg = upsert3dsBlock(cfg, BLOCK_BIRTHDAY, new byte[] { (byte) month, (byte) day }, (short) 0x000E);
                if (!java.util.Arrays.equals(cfg, original)) GameSession.writeAtomically(configFile, cfg);
            } catch (IOException ignored) { }
        }
    }

    private static byte[] encode3dsUsername(String nickname) {
        // 3DS Username block is 0x1C (28) bytes: 20 bytes UTF-16LE + 2-byte null + flags
        byte[] out = new byte[0x1C];
        byte[] utf16 = nickname.getBytes(StandardCharsets.UTF_16LE);
        System.arraycopy(utf16, 0, out, 0, Math.min(20, utf16.length));
        return out;
    }

    /**
     * Finds a block by ID in the 3DS config table and updates its payload,
     * or appends a new block entry if it is not present yet.
     */
    private static byte[] upsert3dsBlock(byte[] buf, int blockId, byte[] payload, short flags) {
        if (buf.length < ENTRY_TABLE) return buf;
        ByteBuffer bb = ByteBuffer.wrap(buf).order(ByteOrder.LITTLE_ENDIAN);
        int totalEntries = bb.getShort(0) & 0xFFFF;
        int dataOffset = bb.getShort(2) & 0xFFFF;

        // 1. Search existing 12-byte block headers. The table starts right after the 4-byte
        //    header (u16 totalEntries, u16 dataOffset), at 0x04, not 0x10.
        for (int i = 0; i < totalEntries; i++) {
            int entryPos = ENTRY_TABLE + (i * 12);
            if (entryPos + 12 > buf.length) break;
            int id = bb.getInt(entryPos);
            if (id == blockId) {
                int size = bb.getShort(entryPos + 8) & 0xFFFF;
                int offsetOrInline = bb.getInt(entryPos + 4);
                if (size <= 4) {
                    // Inline 4-byte payload stored directly in header bytes +4..+7
                    for (int b = 0; b < 4; b++) {
                        buf[entryPos + 4 + b] = b < payload.length ? payload[b] : 0;
                    }
                } else if (offsetOrInline >= 0 && offsetOrInline + size <= buf.length) {
                    int copyLen = Math.min(size, payload.length);
                    for (int b = 0; b < size; b++) buf[offsetOrInline + b] = 0;
                    System.arraycopy(payload, 0, buf, offsetOrInline, copyLen);
                }
                return buf;
            }
        }

        // 2. Append new entry if space allows
        int newEntryPos = ENTRY_TABLE + (totalEntries * 12);
        int neededDataBytes = payload.length <= 4 ? 0 : payload.length;
        int newDataOffset = dataOffset - neededDataBytes;
        if (newEntryPos + 12 > newDataOffset || newDataOffset < 0) {
            return buf; // Config buffer full
        }

        bb.putInt(newEntryPos, blockId);
        if (payload.length <= 4) {
            for (int b = 0; b < 4; b++) {
                buf[newEntryPos + 4 + b] = b < payload.length ? payload[b] : 0;
            }
        } else {
            System.arraycopy(payload, 0, buf, newDataOffset, payload.length);
            bb.putInt(newEntryPos + 4, newDataOffset);
        }
        bb.putShort(newEntryPos + 8, (short) payload.length);
        bb.putShort(newEntryPos + 10, flags);

        bb.putShort(0, (short) (totalEntries + 1));
        bb.putShort(2, (short) newDataOffset);
        return buf;
    }
}