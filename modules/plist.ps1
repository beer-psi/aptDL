<#
MIT License

Copyright (c) 2019 Carl Morris

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

<#
.SYNOPSIS
    Convert a XML Plist to a PowerShell object
.DESCRIPTION
    Converts an XML PList (property list) in to a usable object in PowerShell.

    Properties will be converted in to ordered hashtables, the values of each property may be integer, double, date/time, boolean, string, or hashtables, arrays of any these, or arrays of bytes.
.EXAMPLE
    $pList = [xml](get-content 'somefile.plist') | ConvertFrom-Plist
.PARAMETER plist
    The property list as an [XML] document object, to be processed.  This parameter is mandatory and is accepted from the pipeline.
.INPUTS
    system.xml.document
.OUTPUTS
    system.object
.NOTES
    Script / Function / Class assembled by Carl Morris, Morris Softronics, Hooper, NE, USA
    Initial release - Aug 27, 2018
    Jan 16, 2021 - Corrected return type of <DATA> tags.
    Sep 19, 2021 - Corrected reaction to empty <DICT>, <ARRAY>, <STRING>, and <DATA> tags.
.LINK
    https://github.com/msftrncs/PwshReadXmlPList
.FUNCTIONALITY
    data format conversion
#>
function ConvertFrom-Plist {
    Param(
        # parameter to pass input via pipeline
        [Parameter(Mandatory, Position = 0,
            ValueFromPipeline, ValueFromPipelineByPropertyName,
            HelpMessage = 'XML Plist object.')]
        [ValidateNotNullOrEmpty()]
        [xml]$plist
    )

    # define a class to provide a method for accelerated processing of the XML tree
    class plistreader {
        # define a static method for accelerated processing of the XML tree
        static [object] processTree ($node) {
            return $(
                <#  iterate through the collection of XML nodes provided, recursing through the children nodes to
                extract properties and their values, dictionaries, or arrays of all, but note that property values
                follow their key, not contained within them. #>
                if ($node.HasChildNodes) {
                    switch ($node.Name) {
                        dict {
                            # for dictionary, return the subtree as a ordered hashtable, with possible recursion of additional arrays or dictionaries
                            $collection = [ordered]@{}
                            $currnode = $node.FirstChild # start at the first child node of the dictionary
                            while ($null -ne $currnode) {
                                if ($currnode.Name -eq 'key') {
                                    # a key in a dictionary, add it to a collection
                                    if ($null -ne $currnode.NextSibling) {
                                        # note: keys are forced to [string], insures a $null key is accepted
                                        $collection[[string][plistreader]::processTree($currnode.FirstChild)] = [plistreader]::processTree($currnode.NextSibling)
                                        $currnode = $currnode.NextSibling.NextSibling # skip the next sibling because it was the value of the property
                                    } else {
                                        throw "Dictionary property value missing!"
                                    }
                                } else {
                                    throw "Non 'key' element found in dictionary: <$($currnode.Name)>!"
                                }
                            }
                            # return the collected hash table
                            $collection
                            continue
                        }
                        array {
                            # for arrays, recurse each node in the subtree, returning an array (forced)
                            , @($node.ChildNodes.foreach{ [plistreader]::processTree($_) })
                            continue
                        }
                        string {
                            # for string, return the value, with possible recursion and collection
                            [plistreader]::processTree($node.FirstChild)
                            continue
                        }
                        integer {
                            # must be an integer type value element, return its value
                            [plistreader]::processTree($node.FirstChild).foreach{
                                # try to determine what size of interger to return this value as
                                if ([int]::TryParse($_, [ref]$null)) {
                                    # a 32bit integer seems to work
                                    $_ -as [int]
                                } elseif ([int64]::TryParse($_, [ref]$null)) {
                                    # a 64bit integer seems to be needed
                                    $_ -as [int64]
                                } else {
                                    # try an unsigned 64bit interger, the largest available here.
                                    $_ -as [uint64]
                                }
                            }
                            continue
                        }
                        real {
                            # must be a floating type value element, return its value
                            [plistreader]::processTree($node.FirstChild) -as [double]
                            continue
                        }
                        date {
                            # must be a date-time type value element, return its value
                            [plistreader]::processTree($node.FirstChild) -as [datetime]
                            continue
                        }
                        data {
                            # must be a data block value element, return its value as [byte[]]
                            , [convert]::FromBase64String([plistreader]::processTree($node.FirstChild))
                            continue
                        }
                        default {
                            # we didn't recognize the element type!
                            throw "Unhandled PLIST property type <$($node.Name)>!"
                        }
                    }
                } else {
                    # some nodes are empty, such as Boolean, others are empty because they have no content (null)
                    switch ($node.Name) {
                        true { $true; continue } # return a Boolean TRUE value
                        false { $false; continue } # return a Boolean FALSE value
                        dict { [ordered]@{}; continue } # return an empty dictionary
                        array { , @(); continue } # return an empty array
                        string { [string]''; continue } # return an empty string
                        data { , [byte[]]@(); continue } # return an empty byte array ([byte[]])
                        default { $node.Value } # return the element value
                    }
                }
            )
        }
    }

    # process the 'plist' item of the input XML object
    [plistreader]::processTree($plist.item('plist').FirstChild)
}