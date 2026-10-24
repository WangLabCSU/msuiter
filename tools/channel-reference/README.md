Bundled reference channel-format files.

Source: SigProfilerSuite/SigProfilerPlotting @ master (commit 9be822faafc9b9933c75b78f0d59f2bfa35d657b),
path sigProfilerPlotting/reference_formats/, license BSD-2-Clause
(see docs/research/04 licensing audit). Fetched 2026-09-28.

Used by tests/testthat/test-channels-reference.R as a permanent
upstream anchor for the canonical channel order (SBS192 has no upstream
reference format; it is derived from SBS384 in data-raw/build_channels.R).

`sigProfilerPlotting-9be822f.py` is the verbatim upstream plotting module
(same repository, same commit, path `sigProfilerPlotting/sigProfilerPlotting.py`,
SHA256 c5ace1456f802c5b6f2d84e702e4bcf4cac493b21e01752dec2916ae967517c6,
fetched 2026-10-24). tests/testthat/test-viz-batch2.R parses the DBS78/ID83
legend palettes out of it as the byte-truth anchor for the M4-03b freeze.

## License of the bundled files

SigProfilerPlotting is distributed under the BSD 2-Clause License:

    Copyright (c) 2019, Erik Bergstrom [Alexandrov Lab]
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice,
       this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
    ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
    LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
    CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
    INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
