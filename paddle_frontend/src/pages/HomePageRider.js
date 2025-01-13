import React, { useState, useEffect } from "react";
import { GoogleMap, Marker, useJsApiLoader } from "@react-google-maps/api";
import NavBar from "../components/NavBar";
import "../styles/HomePageRider.css";

const HomePageRider = () => {
  const googleMapsApiKey = process.env.REACT_APP_GOOGLE_MAPS_KEY;

  // State for user location and errors
  const [userLocation, setUserLocation] = useState(null);
  const [error, setError] = useState(null);

  // Use the useJsApiLoader hook
  const { isLoaded, loadError } = useJsApiLoader({
    id: "google-map-script",
    googleMapsApiKey,
    libraries: ["geometry", "drawing"],
  });

  // Watch for user location changes
  useEffect(() => {
    const watchId = navigator.geolocation.watchPosition(
      (position) => {
        const { latitude, longitude } = position.coords;
        console.log(`Latitude: ${latitude}, Longitude: ${longitude}`);
        setUserLocation({ lat: latitude, lng: longitude });
        setError(null);
      },
      (err) => {
        console.error("Geolocation error:", err.message);
        setError(err.message);
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 0,
      }
    );

    return () => {
      navigator.geolocation.clearWatch(watchId);
    };
  }, []);

  if (loadError) {
    return <div className="error-message">Error loading Google Maps API</div>;
  }

  return (
    <div className="main-page">
      <NavBar />
      <div className="map-container">
        {error ? (
          <div className="error-message">
            <p>We couldn't access your location.</p>
            <p>
              Please enable location services in your browser settings or allow
              location access when prompted.
            </p>
          </div>
        ) : !isLoaded ? (
          <div className="loading-message">Loading Google Maps...</div>
        ) : (
          <GoogleMap
            center={userLocation || { lat: 51.505, lng: -0.09 }} // Default if userLocation is null
            zoom={13}
            mapContainerStyle={{ height: "100%", width: "100%" }}
            options={{
              streetViewControl: false,
              fullscreenControl: false,
            }}
          >
            {userLocation && (
              <Marker
                position={userLocation}
                icon={{
                  url: "https://maps.google.com/mapfiles/ms/icons/blue-dot.png",
                  scaledSize: new window.google.maps.Size(40, 40),
                }}
              />
            )}
          </GoogleMap>
        )}
      </div>
    </div>
  );
};

export default HomePageRider;
