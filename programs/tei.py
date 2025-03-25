LLDQ = "\u201E"  # low left double quotation mark „ (vim digraph :9)


def transform(text):
    return text.replace(",,", LLDQ)
