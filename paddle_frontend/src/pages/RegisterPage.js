import React, { useState } from "react";
import { Box, Button, TextField, Typography, CircularProgress, FormControlLabel, Checkbox } from "@mui/material";
import { useNavigate } from "react-router-dom";
import "../styles/RegisterPage.css";
import { registerUser } from "../utils/api";
import saveToLocalStorage from "../utils/utils";

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
    latitude: "0",
    longitude: "0"
  });

  const [isOwner, setIsOwner] = useState(false);
  const [isLoading, setIsLoading] = useState(false); // Loading screen
  const [socket, setSocket] = useState(null); // Track WebSocket connection

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData({ ...formData, [name]: value });
  };

  const handleCheckboxChange = (e) => {
    setIsOwner(e.target.checked);
  };

  const handleSubmit = async (e) => {
    // TODO: Remove this temporary token fallback
    localStorage.clear();

    e.preventDefault();

    try {
      const response = await registerUser(formData, isOwner);
      const { message, verification_url, websocket_url } = response;

      console.log(message);
      console.log(verification_url);

      if (verification_url && websocket_url) {
        setIsLoading(true);
        window.open(verification_url, "_blank");

        let shouldCloseModal = true;
        const ws = new WebSocket(websocket_url);

        ws.onopen = () => {
          console.log("WebSocket connection established.");
        };

        ws.onmessage = (event) => {
          const data = JSON.parse(event.data);
          console.log(data);

          if (data.type === "verification_complete" || data.type === "status_update") {
            if (data.status === "verified") {
              shouldCloseModal = false;
              console.log("Verification successful:", data);
              ws.close(1000);
              saveToLocalStorage(data.user);
              setTimeout(() => {
                setIsLoading(false);
                navigate("/home", {state: { isOwner }});
              }, 2000);
            } else if (data.status === "failed" || data.status === "canceled") {
              console.error("Verification failed:", data.message);
              ws.close();
              alert("Verification failed. Please try again.");
              setIsLoading(false);
            }
          }
        };

        ws.onerror = (error) => {
          console.error("WebSocket error:", error);
          alert("An error occurred during the verification process.");
          ws.close();
          setIsLoading(false);
        };

        ws.onclose = () => {
          console.log("WebSocket connection closed.");
          if (shouldCloseModal) setIsLoading(false);
        };

        setSocket(ws);
      }
    } catch (error) {
      console.error("Registration failed:", error.message);
    }
  };

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
          <FormControlLabel
            control={
              <Checkbox
                checked={isOwner}
                onChange={handleCheckboxChange}
                color="primary"
              />
            }
            label="Log in as an owner"
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
