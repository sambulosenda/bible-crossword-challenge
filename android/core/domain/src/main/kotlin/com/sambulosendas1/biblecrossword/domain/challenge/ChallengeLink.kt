package com.sambulosendas1.biblecrossword.domain.challenge

import java.net.URI

/**
 * The friend-challenge link, with no backend — iOS `Services/ChallengeService.swift`.
 * A solved puzzle becomes a URL; the recipient's app parses it back.
 *
 * Two shapes carry the identical query: the https universal link (what players
 * actually send — tappable anywhere, and it opens the web landing page for
 * anyone without the app) and the custom scheme (a parseable fallback).
 * Family boards ride the same `/challenge/` path and are told apart by their
 * query, not the path.
 */
object ChallengeLink {

    data class Challenge(val puzzleID: String, val challengerName: String, val seconds: Int)

    sealed interface ParseOutcome {
        /** Well-formed, for a puzzle this build knows — play it. */
        data class Valid(val challenge: Challenge) : ParseOutcome
        /** Structurally a challenge but from a newer payload, or a puzzle this bundle lacks. */
        data object NeedsUpdate : ParseOutcome
        /** Not a challenge link, or malformed — ignore. */
        data object NotAChallenge : ParseOutcome
    }

    const val CURRENT_VERSION = 1
    const val SCHEME = "biblecrossword"
    const val HOST = "challenge"
    const val WEB_HOST = "biblecrosswordchallenge.com"
    const val WEB_PATH = "/challenge/"
    const val PLACEHOLDER_NAME = "A friend"

    private const val MAX_NAME_LENGTH = 20
    /** A day — clamps absurd or hostile values. */
    private const val MAX_SECONDS = 86_400

    /**
     * Whether a URL is addressed to the challenge endpoint at all: the custom
     * scheme, or the https link on the web host or any subdomain of it.
     */
    fun isChallengeLink(uri: URI): Boolean {
        if (uri.scheme == SCHEME && uri.host == HOST) return true
        val host = uri.host ?: return false
        return uri.scheme == "https" &&
            (host == WEB_HOST || host.endsWith(".$WEB_HOST")) &&
            (uri.path ?: "").startsWith("/challenge")
    }

    /**
     * [puzzleExists] is injected so the rule is testable without a bundle —
     * and so an unknown id resolves to "update the app" rather than a crash.
     */
    fun parse(raw: String, puzzleExists: (String) -> Boolean): ParseOutcome {
        val uri = runCatching { URI(raw) }.getOrNull() ?: return ParseOutcome.NotAChallenge
        if (!isChallengeLink(uri)) return ParseOutcome.NotAChallenge

        val query = parseQuery(uri.rawQuery)

        // A newer payload than we understand can't be trusted to have the same
        // fields — send the player to the store instead of guessing.
        val version = query["v"]?.toIntOrNull() ?: return ParseOutcome.NotAChallenge
        if (version > CURRENT_VERSION) return ParseOutcome.NeedsUpdate

        val puzzleID = query["p"]?.takeIf { it.isNotEmpty() } ?: return ParseOutcome.NotAChallenge
        val seconds = query["t"]?.toIntOrNull() ?: return ParseOutcome.NotAChallenge
        if (seconds !in 1..MAX_SECONDS) return ParseOutcome.NotAChallenge

        // Trim + cap, falling back to a neutral label rather than "beat  :".
        val rawName = (query["n"] ?: "").trim()
        val name = if (rawName.isEmpty()) PLACEHOLDER_NAME else rawName.take(MAX_NAME_LENGTH)

        if (!puzzleExists(puzzleID)) return ParseOutcome.NeedsUpdate

        return ParseOutcome.Valid(Challenge(puzzleID, name, seconds))
    }

    /** The https universal link to share — what players actually send. */
    fun webURL(puzzleID: String, seconds: Int, name: String): String =
        "https://$WEB_HOST$WEB_PATH?" + query(puzzleID, seconds, name)

    /** The custom-scheme equivalent, kept as a parseable fallback. */
    fun schemeURL(puzzleID: String, seconds: Int, name: String): String =
        "$SCHEME://$HOST?" + query(puzzleID, seconds, name)

    private fun query(puzzleID: String, seconds: Int, name: String): String =
        "v=$CURRENT_VERSION" +
            "&p=${encode(puzzleID)}" +
            "&t=$seconds" +
            // Capped before encoding, so the cap counts characters not bytes.
            "&n=${encode(name.take(MAX_NAME_LENGTH))}"

    /**
     * RFC 3986 percent-encoding of a query value: everything but the
     * unreserved set. Matches what `URLComponents` emits on iOS (space → `%20`,
     * `&` → `%26`) — `java.net.URLEncoder` would give `+` for space and break
     * link parity.
     */
    private fun encode(value: String): String = buildString {
        for (byte in value.toByteArray(Charsets.UTF_8)) {
            val c = byte.toInt().toChar()
            if (c.isLetterOrDigit() && c.code < 128 || c in "-._~") append(c)
            else append("%%%02X".format(byte.toInt() and 0xFF))
        }
    }

    private fun parseQuery(rawQuery: String?): Map<String, String> {
        if (rawQuery.isNullOrEmpty()) return emptyMap()
        val out = LinkedHashMap<String, String>()
        for (pair in rawQuery.split("&")) {
            if (pair.isEmpty()) continue
            val i = pair.indexOf('=')
            if (i < 0) continue
            val key = decode(pair.substring(0, i))
            val value = decode(pair.substring(i + 1))
            // First wins, matching how iOS folds repeated items into a dictionary.
            out.putIfAbsent(key, value)
        }
        return out
    }

    private fun decode(value: String): String =
        runCatching { java.net.URLDecoder.decode(value.replace("+", "%2B"), "UTF-8") }.getOrDefault(value)
}
