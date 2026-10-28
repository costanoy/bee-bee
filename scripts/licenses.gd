extends RefCounted

# What the credits screen says (pause menu > Credits): who made what, and
# the licence notices the game has to carry. Godot's own and those of the
# third-party code inside it are asked from the engine at run time, so they
# always match the engine version that was actually shipped; the font's and
# the plugins' are copied here from fonts/ and addons/, because plain text
# files are not included in an export.
#
# The lines that are the game's own come in the game's language; the
# licence notices stay in English, the language they were written in.

# Who made the game and who owns it, as the user asked to be credited.
const CREATOR := "Vinicius Costa"
const OWNER := "Cyberhat"
const YEAR := 2026

const OWN_LINES := {
	"en": {
		"created": "Created by %s.",
		"owner": "© %d %s. All rights reserved.",
		"audio": "Music made with Suno (suno.com). Sound effects made with ElevenLabs (elevenlabs.io).",
		"godot": "This game uses Godot Engine, available under the following license:",
		"font": "Jersey 10 (font)",
		"third_party": "Third-party software in Godot Engine",
		"android": "Android libraries",
	},
	"pt": {
		"created": "Criado por %s.",
		"owner": "© %d %s. Todos os direitos reservados.",
		"audio": "Música feita com Suno (suno.com). Efeitos sonoros feitos com ElevenLabs (elevenlabs.io).",
		"godot": "Este jogo usa a Godot Engine, disponível sob a licença abaixo:",
		"font": "Jersey 10 (fonte)",
		"third_party": "Software de terceiros na Godot Engine",
		"android": "Bibliotecas do Android",
	},
}

const FONT_NOTICE := """Copyright 2023 The Soft Type Project Authors (https://github.com/scfried/soft-type-jersey)

This Font Software is licensed under the SIL Open Font License, Version 1.1. This license is copied below, and is also available with a FAQ at: https://openfontlicense.org

-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE The goals of the Open Font License (OFL) are to stimulate worldwide development of collaborative font projects, to support the font creation efforts of academic and linguistic communities, and to provide a free and open framework in which fonts may be shared and improved in partnership with others.

The OFL allows the licensed fonts to be used, studied, modified and redistributed freely as long as they are not sold by themselves. The fonts, including any derivative works, can be bundled, embedded, redistributed and/or sold with any software provided that any reserved names are not used by derivative works. The fonts and derivatives, however, cannot be released under any other type of license. The requirement for fonts to remain under this license does not apply to any document created using the fonts or their derivatives.

DEFINITIONS "Font Software" refers to the set of files released by the Copyright Holder(s) under this license and clearly marked as such. This may include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the copyright statement(s).

"Original Version" refers to the collection of Font Software components as distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting, or substituting -- in part or in whole -- any of the components of the Original Version, by changing formats or by porting the Font Software to a new environment.

"Author" refers to any designer, engineer, programmer, technical writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS Permission is hereby granted, free of charge, to any person obtaining a copy of the Font Software, to use, study, copy, merge, embed, modify, redistribute, and sell modified and unmodified copies of the Font Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components, in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled, redistributed and/or sold with any software, provided that each copy contains the above copyright notice and this license. These can be included either as stand-alone text files, human-readable headers or in the appropriate machine-readable metadata fields within text or binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font Name(s) unless explicit written permission is granted by the corresponding Copyright Holder. This restriction only applies to the primary font name as presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font Software shall not be used to promote, endorse or advertise any Modified Version, except to acknowledge the contribution(s) of the Copyright Holder(s) and the Author(s) or with their explicit written permission.

5) The Font Software, modified or unmodified, in part or in whole, must be distributed entirely under this license, and must not be distributed under any other license. The requirement for fonts to remain under this license does not apply to any document created using the Font Software.

TERMINATION This license becomes null and void if any of the above conditions are not met.

DISCLAIMER THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM OTHER DEALINGS IN THE FONT SOFTWARE."""

const MIT_TERMS := """Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."""


# The Android build bundles the AdMob plugin's Java and Kotlin dependencies,
# which carry their own notices. The list comes from the APK itself
# (META-INF/*.version, the *.properties files and the packages in its dex
# files); check it again when the plugin or the Godot version changes. The
# Apache, BSD and MPL texts are not repeated here: the engine's licence
# list, at the end of the credits, already has all three in full.
const ANDROID_NOTICES := [
	"The Android version of this game includes the following open-source libraries. Their licence texts are given in full at the end of these credits, under Apache-2.0, BSD-3-clause and MPL-2.0; the MIT terms are given under Plugins above.",
	"Licensed under the Apache License, Version 2.0:",
	"AndroidX (Android Jetpack): Activity, Annotation, AppCompat, Arch Core, Browser, Collection, Concurrent Futures, ConstraintLayout, Core, CursorAdapter, CustomView, DataStore, DocumentFile, DrawerLayout, Fragment, Interpolator, Lifecycle, Loader, ProfileInstaller, Room, SavedState, SQLite, Startup, Tracing, VectorDrawable, VersionedParcelable, ViewPager, WebKit and WorkManager. Copyright (c) The Android Open Source Project.",
	"Kotlin Standard Library, kotlinx.coroutines and kotlinx-atomicfu. Copyright (c) JetBrains s.r.o. and Kotlin Programming Language contributors.",
	"Guava: Google Core Libraries for Java. Copyright (c) The Guava Authors.",
	"Tink. Copyright (c) Google LLC.",
	"Gson. Copyright (c) Google Inc.",
	"OkHttp and Okio. Copyright (c) Square, Inc.",
	"Error Prone annotations, J2ObjC annotations. Copyright (c) Google Inc. JetBrains Java Annotations. Copyright (c) JetBrains s.r.o. JSpecify annotations. Copyright (c) The JSpecify Authors.",
	"LLVM libc++ (Apache License 2.0 with LLVM Exceptions). Copyright (c) LLVM Project contributors.",
	"Licensed under the BSD 3-Clause License: Protocol Buffers (Java Lite). Copyright (c) Google Inc. Cronet API. Copyright (c) The Chromium Authors.",
	"Licensed under the MIT License: Checker Framework qualifiers. Copyright (c) the Checker Framework developers.",
	"Licensed under the Mozilla Public License 2.0: the Public Suffix List (publicsuffix.org), as included in OkHttp.",
	"The Google Mobile Ads SDK, the Google User Messaging Platform SDK and Google Play services are provided by Google LLC under Google's own terms.",
]


# The text as a list of [is_heading, text] blocks: the screen makes one
# label of each, so only the ones in view are drawn. `lang` is a key of
# OWN_LINES (main.gd's language).
static func blocks(lang := "en") -> Array:
	var own: Dictionary = OWN_LINES.get(lang, OWN_LINES["en"])
	var out := []
	out.append([true, "Bee Bee"])
	out.append([false, own["created"] % CREATOR])
	out.append([false, own["owner"] % [YEAR, OWNER]])
	out.append([false, own["audio"]])

	out.append([true, "Godot Engine"])
	out.append([false, own["godot"]])
	for part in _paragraphs(Engine.get_license_text()):
		out.append([false, part])

	out.append([true, own["font"]])
	for part in FONT_NOTICE.split("\n\n"):
		out.append([false, part])

	out.append([true, "Plugins"])
	out.append([false, "Godot AdMob Plugin. Copyright (c) 2020-present Poing Studios. MIT License."])
	out.append([false, "Godot Play Game Services. Copyright (c) 2023 Jacob Ibáñez Sánchez. MIT License."])
	for part in MIT_TERMS.split("\n\n"):
		out.append([false, part])

	out.append([true, own["android"]])
	for part in ANDROID_NOTICES:
		out.append([false, part])

	out.append([true, own["third_party"]])
	for component in Engine.get_copyright_info():
		var lines := PackedStringArray([component["name"]])
		for part in component["parts"]:
			for owner in part["copyright"]:
				lines.append("  (c) " + owner)
			lines.append("  License: " + part["license"])
		out.append([false, "\n".join(lines)])

	var licenses := Engine.get_license_info()
	for id in licenses:
		out.append([true, id])
		for part in _paragraphs(String(licenses[id])):
			out.append([false, part])
	return out


# The engine's texts come wrapped at 80 columns, which a narrow screen then
# wraps again in the wrong places. This splits a text into its paragraphs
# and lets each flow as one line; a paragraph with indented lines (a list,
# a table) is left as it is.
static func _paragraphs(text: String) -> Array:
	var out := []
	for part in text.split("\n\n"):
		if part.strip_edges() == "":
			continue
		var lines := part.split("\n")
		var plain := true
		for i in range(1, lines.size()):
			if lines[i].begins_with(" ") or lines[i].begins_with("\t"):
				plain = false
		if plain:
			var flowed := PackedStringArray()
			for line in lines:
				flowed.append(line.strip_edges())
			out.append(" ".join(flowed))
		else:
			out.append(part)
	return out
