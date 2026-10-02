extends RefCounted

# What the credits screen says (pause menu > Credits): who made what, and
# the licence notices the game has to carry. Godot's own and those of the
# third-party code inside it are asked from the engine at run time, so they
# always match the engine version that was actually shipped; the font's and
# the plugins' are copied here from fonts/ and addons/, because plain text
# files are not included in an export.
#
# Fill in DEVELOPER to have a "made by" line at the top.

const DEVELOPER := ""

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


# The text as a list of [is_heading, text] blocks: the screen makes one
# label of each, so only the ones in view are drawn.
static func blocks() -> Array:
	var out := []
	out.append([true, "Bee Bee"])
	if DEVELOPER != "":
		out.append([false, "A game by %s." % DEVELOPER])
	out.append([false, "Music and sound effects made with ElevenLabs (elevenlabs.io)."])

	out.append([true, "Godot Engine"])
	out.append([false, "This game uses Godot Engine, available under the following license:"])
	for part in _paragraphs(Engine.get_license_text()):
		out.append([false, part])

	out.append([true, "Jersey 10 (font)"])
	for part in FONT_NOTICE.split("\n\n"):
		out.append([false, part])

	out.append([true, "Plugins"])
	out.append([false, "Godot AdMob Plugin. Copyright (c) 2020-present Poing Studios. MIT License."])
	out.append([false, "Godot Play Game Services. Copyright (c) 2023 Jacob Ibáñez Sánchez. MIT License."])
	for part in MIT_TERMS.split("\n\n"):
		out.append([false, part])

	out.append([true, "Third-party software in Godot Engine"])
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
