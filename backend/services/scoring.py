def calculate_score(current_score: float, symbol: str, value: float) -> float:
    if symbol == "+":
        return current_score + value
    if symbol == "-":
        return current_score - value
    if symbol == "×" or symbol == "x" or symbol == "X" or symbol == "*":
        return current_score * value
    if symbol == "÷" or symbol == "/":
        return current_score / value if value != 0 else current_score
    return current_score
