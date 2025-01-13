import React, { useState, useEffect } from "react";
import { Box, Button, TextField, Typography, CircularProgress } from "@mui/material";
import { useNavigate } from "react-router-dom";
import "../styles/RegisterPage.css";
import { registerUser, getVerificationStatus } from "../utils/api";

const RegisterPage = () => {
  const navigate = useNavigate();
  const [formData, setFormData] = useState({
    username: "",
    email: "",
    password: "",
    phone_number: "",
    address: "",
    cpn: "",
    age: "",
  });

  const [isLoading, setIsLoading] = useState(false); // Loading screen for verification process
  const [polling, setPolling] = useState(false);
  const [retryCount, setRetryCount] = useState(0); // Track polling retries

  const maxRetries = 10; // Maximum number of retries
  const verificationSuccessDelay = 2000; // Delay after successful verification

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData({ ...formData, [name]: value });
  };

  const handleSubmit = async (e) => {
    // TODO: Remove this temporary token fallback
    localStorage.clear();

    e.preventDefault();
    
    try {
      const response = await registerUser(formData); // API call to register the user
      const { message, verification_url, access, refresh, user_id } = response;
      
      localStorage.setItem("access_token", access);
      
      console.log(message);
      console.log(verification_url);
      
      if (verification_url) {
        setIsLoading(true);
        window.open(verification_url, "_blank");

        // Start polling for verification status
        setPolling(true);
      }
    } catch (error) {
      // console.error("Registration failed:", error.message);
    }
  };

  useEffect(() => {
    let interval;

    if (polling && retryCount < maxRetries) {
      // Hitting the backend with a stick every 6 seconds to see if verification is complete
      interval = setInterval(async () => {
        try {
          const response = await getVerificationStatus(formData.username);
          console.log("Verification Status:", response.status);

          if (response.status === "verified") {
            setPolling(false);
            clearInterval(interval);

            // Add delay before deactivating the loading screen and redirecting user
            setTimeout(() => {
              alert("Verification completed successfully!");
              setIsLoading(false);
              navigate("/home");
            }, verificationSuccessDelay);
          } else {
            // Increment the retry counter if not verified
            setRetryCount((prev) => prev + 1);
          }
        } catch (error) {
          console.error("Error checking verification status:", error.message);
          setPolling(false);
          setIsLoading(false);
          alert("Verification process failed. Please try again.");
        }
      }, 6000);
    }

    if (retryCount >= maxRetries) {
      setPolling(false);
      setIsLoading(false);
      alert("Verification process failed. Please try again.");
    }

    return () => {
      if (interval) clearInterval(interval);
    };
  }, [polling, retryCount]);


  return (
    <div className="register-page">
      {isLoading && (
        <div className="loading-overlay">
          <CircularProgress />
          <Typography variant="body1" sx={{ mt: 2, color: "white" }}>
            Registering... Please wait.
          </Typography>
        </div>
      )}

      <div className="background-image"></div>
      <Box className="form-box">
        <Typography variant="h4" gutterBottom>
          Register
        </Typography>
        <form onSubmit={handleSubmit}>
          <TextField
            fullWidth
            required
            label="Username"
            name="username"
            value={formData.username}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            required
            type="email"
            label="Email"
            name="email"
            value={formData.email}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            required
            type="password"
            label="Password"
            name="password"
            value={formData.password}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            required
            label="Phone Number"
            name="phone_number"
            value={formData.phone_number}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            required
            label="Address"
            name="address"
            value={formData.address}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            required
            label="CNP"
            name="cpn"
            value={formData.cpn}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            label="Age"
            name="age"
            value={formData.age}
            onChange={handleInputChange}
            margin="normal"
          />
          <Button
            variant="contained"
            color="primary"
            type="submit"
            size="large"
            fullWidth
            sx={{ mt: 3 }}
          >
            Register
          </Button>
        </form>
      </Box>
    </div>
  );
};

export default RegisterPage;
