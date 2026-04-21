def calculate_price(distance, duration_hours):
    base_fare = 2.00
    rate_per_km = 1.50
    rate_per_hour = 10.00
    
    distance_cost = distance * rate_per_km
    duration_cost = duration_hours * rate_per_hour
    
    total_price = base_fare + distance_cost + duration_cost
    return round(total_price, 2)
