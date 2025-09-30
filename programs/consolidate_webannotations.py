#!/usr/bin/env python

import argparse
import json
import sys
from typing import Optional
from collections import OrderedDict

ID_SUFFIX = ".normal"
NEW_TYPE = "NormalText"
ORIGINAL_TYPE = "OriginalText"

def set_target_type(webannotation: dict, target_type: str, length: Optional[int] = None) -> dict:
    if isinstance(webannotation['target'], list):
        for i, target in enumerate(webannotation['target']):
            if length is not None and i >= length:
                break
            if isinstance(target,str) and target.startswith("POSTPROCESS:"):
                #only process things that were marked for postprocessing
                webannotation['target'][i] = {
                    "type": target_type,
                    "source": target[12:]
                }
    else:
        raise TypeError("expected target list")
    return webannotation

def main():
    parser = argparse.ArgumentParser(description="Consolidate multiple webannotations by merging secondary ones into the primary one. Uses standard input and standard output (JSONL)")
    _ = parser.parse_args()

    passed = 0 
    webannotations = OrderedDict()
    for line in sys.stdin:
        webannotation = json.loads(line)
        if 'id' in webannotation:
            webannotations[webannotation['id']] = webannotation
        elif line:
            #id-less annotation, nothing to merge, output-as is (blank node) but use the new type
            passed += 1
            print(json.dumps(set_target_type(webannotation, NEW_TYPE), ensure_ascii=False, indent=None))

    merged = 0
    skipped = 0
    potential = 0
    for id, webannotation in webannotations.items():
        if not id.endswith(ID_SUFFIX): #not a secondary suffix
            if id.endswith((".translation-source",".translation-target","-translated","-translationsource")) or ('body' in webannotation and 'https://w3id.org/stam/extensions/stam-translate/Translation' in webannotation['body']):
                #skip translation annotations
                skipped += 1
                continue
            try:
                #find the secondary annotation that we merge into the current (primary) one
                secondary_id = id + ID_SUFFIX
                secondary = webannotations[secondary_id]
            except KeyError:
                #no secondary, primary web annotation is already the normal text, call it NormalText
                passed += 1
                print(json.dumps(set_target_type(webannotation, NEW_TYPE), ensure_ascii=False, indent=None))
                continue
            merged += 1
            original_length = len(webannotation['target'])
            for target in secondary['target']:
                if isinstance(target,str) and target not in webannotation['target'] and target.startswith("POSTPROCESS:"):
                    #add the normal text
                    webannotation['target'].append(
                        {
                            "type": NEW_TYPE,
                            "source": target[12:]
                        })
            #what was there before will be original text
            webannotation = set_target_type(webannotation, ORIGINAL_TYPE, original_length),
            print(json.dumps(webannotation, ensure_ascii=False, indent=None))
        else:
            potential +=  1

    print(f"Merged {merged} (out of {potential}) annotations, passed {passed}, skipped {skipped}",file=sys.stderr)

if __name__ == "__main__":
    main()
