CREATE TABLE trips (
    id BIGINT PRIMARY KEY,
    vendor_id INT,
    pickup_datetime TIMESTAMP,
    dropoff_datetime TIMESTAMP,
    passenger_count INT,
    trip_distance NUMERIC(10,2),
    rate_code_id INT,
    store_and_fwd_flag VARCHAR(1),
    pickup_location_id INT,
    dropoff_location_id INT,
    payment_type INT,
    fare_amount NUMERIC(10,2),
    extra NUMERIC(10,2),
    mta_tax NUMERIC(10,2),
    tip_amount NUMERIC(10,2),
    tolls_amount NUMERIC(10,2),
    improvement_surcharge NUMERIC(10,2),
    total_amount NUMERIC(10,2),
    congestion_surcharge NUMERIC(10,2),
    rider_email VARCHAR(100),
    driver_email VARCHAR(100),
    driver_name VARCHAR(100),
    vehicle_id VARCHAR(50),
    cab_type_id INT
);


CREATE SEQUENCE trips_id_seq START WITH 2000000;
ALTER TABLE trips ALTER COLUMN id SET DEFAULT nextval('trips_id_seq');


SELECT table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'trips';